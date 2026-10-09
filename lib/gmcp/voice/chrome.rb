# frozen_string_literal: true

require 'json'
require 'open3'
require 'openssl'

module GMCP
  module Voice
    # Google Voice has no OAuth scope, so its session is a set of google.com
    # cookies. GMCP reads them from the Chrome profile already signed in to the
    # account, found by email in Chrome's Local State. Chrome keeps that
    # session alive as it is used, so GMCP never signs in or refreshes anything
    # itself, and an account with no Chrome profile simply has no Voice.
    #
    # macOS only. Chrome encrypts cookie values with AES-128-CBC under a key
    # derived from the "Chrome Safe Storage" Keychain item; reading that item
    # asks the user once, and "Always Allow" makes it silent thereafter.
    module Chrome
      class Error < StandardError; end

      KEYCHAIN_SERVICE = 'Chrome Safe Storage'

      # Cookie values are "v10" + AES-128-CBC(key, iv: 16 spaces). The key is
      # PBKDF2-SHA1 of the Keychain secret, salt "saltysalt", 1003 rounds.
      ENCRYPTED_PREFIX = 'v10'
      # From cookie DB version 24 the plaintext starts with SHA-256(host_key).
      HOST_DIGEST_VERSION = 24
      # Chrome timestamps count microseconds from 1601-01-01.
      CHROME_EPOCH_OFFSET = 11_644_473_600

      QUERY = <<~SQL.tr("\n", ' ')
        SELECT host_key, name, hex(encrypted_value) AS value, expires_utc
        FROM cookies WHERE host_key = '.google.com' OR host_key LIKE '%.google.com'
      SQL

      class << self
        def dir
          File.expand_path(ENV.fetch('GMCP_CHROME_DIR', '~/Library/Application Support/Google/Chrome'))
        end

        # The account's google.com session cookies, as { name => value }.
        def cookies(account)
          db = File.join(profile_for(account), 'Cookies')
          raise Error, "Chrome profile for #{account} has no cookie store" unless File.exist?(db)

          version = Integer(sqlite(db, "SELECT value FROM meta WHERE key = 'version'").dig(0, 'value'))
          now = Time.now.to_i
          sqlite(db, QUERY)
            .reject { |row| expired?(row['expires_utc'], now) }
            .sort_by { |row| row['host_key'] == '.google.com' ? 1 : 0 } # the shared domain wins on a name clash
            .to_h { |row| [row['name'], decrypt([row['value']].pack('H*'), version)] }
        end

        # The profile directory signed in as account. Chrome records each
        # profile's Google account in Local State's info_cache.
        def profile_for(account)
          state = JSON.parse(File.read(File.join(dir, 'Local State')))
          name, = state.dig('profile', 'info_cache')&.find { |_dir, info| info['user_name'].to_s.casecmp?(account) }
          raise Error, "No Chrome profile is signed in as #{account}. Sign in to Chrome with that account." unless name

          File.join(dir, name)
        rescue Errno::ENOENT
          raise Error, "Google Chrome is not set up here (no #{File.join(dir, 'Local State')})"
        end

        def decrypt(blob, version)
          return blob.force_encoding(Encoding::UTF_8) unless blob.start_with?(ENCRYPTED_PREFIX)

          cipher = OpenSSL::Cipher.new('aes-128-cbc').decrypt
          cipher.key = key
          cipher.iv = ' ' * 16
          plain = cipher.update(blob.byteslice(ENCRYPTED_PREFIX.bytesize..)) + cipher.final
          plain = plain.byteslice(32..) if version >= HOST_DIGEST_VERSION
          plain.force_encoding(Encoding::UTF_8)
        rescue OpenSSL::Cipher::CipherError
          raise Error, 'Could not decrypt Chrome cookies; the Chrome Safe Storage key did not match'
        end

        # Test seam.
        def reset!
          @key = nil
        end

        private

        def key
          @key ||= begin
            secret, status = Open3.capture2('security', 'find-generic-password', '-w', '-s', KEYCHAIN_SERVICE)
            raise Error, "Keychain access to #{KEYCHAIN_SERVICE} was denied" unless status.success?

            OpenSSL::PKCS5.pbkdf2_hmac_sha1(secret.chomp, 'saltysalt', 1003, 16)
          end
        end

        # Read through sqlite3's immutable mode, so Chrome's own lock on the
        # live database neither blocks the read nor is disturbed by it.
        def sqlite(db, query)
          out, err, status = Open3.capture3('sqlite3', '-json', "file:#{db}?mode=ro&immutable=1", query)
          raise Error, "Could not read #{db}: #{err.strip}" unless status.success?

          out.strip.empty? ? [] : JSON.parse(out)
        end

        def expired?(expires_utc, now)
          micros = expires_utc.to_i
          micros.positive? && (micros / 1_000_000) - CHROME_EPOCH_OFFSET < now
        end
      end
    end
  end
end
