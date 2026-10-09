# frozen_string_literal: true

# Reads cookies from Safari's Cookies.binarycookies file.
# Format reference: https://github.com/interpals/BinaryCookieReader (public domain)
#
# Layout:
#   Header  : "cook" + num_pages (uint32 BE) + [page_size (uint32 BE)] * num_pages
#   Page    : 0x00000100 + num_cookies (uint32 LE) + [cookie_offset (uint32 LE)] * num_cookies
#             + 0x00000000 + cookies
#   Cookie  : size (uint32 LE) + 4 unknown + flags + 4 unknown
#             + url_offset + name_offset + path_offset + value_offset (all uint32 LE)
#             + 8 zero bytes + expiry (f64 LE, Mac epoch) + creation (f64 LE, Mac epoch)
#             + url + name + path + value (all NUL-terminated strings)

module GMCP
  module Voice
    module SafariCookies
      # Sandboxed Safari (macOS 10.14+) keeps its store inside its container;
      # the legacy location is still where older systems, and some migrated
      # accounts, have it. Container first, because when both exist the legacy
      # file is the stale one.
      PATHS = [
        File.expand_path('~/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies'),
        File.expand_path('~/Library/Cookies/Cookies.binarycookies')
      ].freeze

      # Cookie expiry is stored as seconds since 2001-01-01 UTC.
      MAC_EPOCH_OFFSET = 978_307_200

      COOKIE_HEADER_SIZE = 56

      class ParseError < StandardError; end

      # Raised when this machine cannot supply Safari cookies at all — a
      # non-macOS host, a Mac where Safari has never stored any, or one where
      # macOS privacy controls deny the read. Distinct from ParseError, which
      # means the file was read but is not what we expect.
      class Unavailable < StandardError; end

      def self.read(domain:, names: nil, path: nil, now: Time.now)
        unless RbConfig::CONFIG['host_os'].to_s.match?(/darwin/)
          raise Unavailable,
                'Google Voice support reads Safari session cookies and therefore ' \
                'only works on macOS. This host is not macOS.'
        end

        path, data = load(path ? [path] : PATHS)
        raise ParseError, "Bad magic in #{path}" unless data.byteslice(0, 4) == 'cook'

        now_mac = now.to_f - MAC_EPOCH_OFFSET
        best = {}
        pages(data).each do |page|
          parse_page(page) do |cookie|
            next unless domain_matches?(cookie[:url], domain)
            next if names && !names.include?(cookie[:name])
            # Zero means the store recorded no expiry; anything else in the past
            # is a cookie Safari would no longer send.
            next if cookie[:expiry].positive? && cookie[:expiry] < now_mac

            current = best[cookie[:name]]
            best[cookie[:name]] = cookie if current.nil? || cookie[:expiry] > current[:expiry]
          end
        end
        best.transform_values { |cookie| cookie[:value] }
      end

      # Returns [path, bytes] for the first candidate that can be read. A
      # permission failure on one candidate does not stop the search, but it is
      # what gets reported if nothing else is readable, because "grant access"
      # is actionable where "not found" would send the user to the wrong fix.
      def self.load(candidates)
        denied = nil
        candidates.each do |path|
          return [path, File.binread(path)]
        rescue Errno::ENOENT, Errno::ENOTDIR
          next
        rescue Errno::EPERM, Errno::EACCES
          denied ||= path
        end

        if denied
          raise Unavailable,
                "macOS denied access to #{denied}. Grant Full Disk Access to the terminal " \
                'app running GMCP (System Settings > Privacy & Security > Full Disk Access), ' \
                'then restart it.'
        end
        raise Unavailable,
              "No Safari cookie store at #{candidates.join(' or ')}. " \
              'Sign in to Google in Safari on this machine first.'
      end
      private_class_method :load

      def self.pages(data)
        num_pages = slice(data, 4, 4).unpack1('L>')
        page_sizes = slice(data, 8, num_pages * 4).unpack("L>#{num_pages}")

        offset = 8 + (num_pages * 4)
        page_sizes.map do |size|
          page = slice(data, offset, size)
          offset += size
          page
        end
      end
      private_class_method :pages

      def self.parse_page(page)
        num_cookies = slice(page, 4, 4).unpack1('L<')
        cookie_offsets = slice(page, 8, num_cookies * 4).unpack("L<#{num_cookies}")
        cookie_offsets.each do |co|
          size = slice(page, co, 4).unpack1('L<')
          raise ParseError, "Cookie record at #{co} is #{size} bytes, smaller than its header" if size < COOKIE_HEADER_SIZE

          rec = slice(page, co, size)
          url_off, name_off, path_off, value_off = rec.byteslice(16, 16).unpack('L<4')
          yield(
            url:    read_cstring(rec, url_off),
            name:   read_cstring(rec, name_off),
            path:   read_cstring(rec, path_off),
            value:  read_cstring(rec, value_off),
            expiry: rec.byteslice(40, 8).unpack1('E')
          )
        end
      end
      private_class_method :parse_page

      # byteslice that refuses to come up short: a truncated or corrupt store
      # must surface as ParseError, not as a nil deep inside an unpack.
      def self.slice(buf, offset, length)
        if offset.negative? || length.negative? || offset + length > buf.bytesize
          raise ParseError, "Cookie store truncated: wanted #{length} bytes at #{offset}, have #{buf.bytesize}"
        end

        buf.byteslice(offset, length)
      end
      private_class_method :slice

      def self.read_cstring(buf, offset)
        raise ParseError, "String offset #{offset} outside a #{buf.bytesize}-byte cookie record" if offset >= buf.bytesize

        terminator = buf.index("\x00".b, offset) || buf.bytesize
        buf.byteslice(offset...terminator).force_encoding('UTF-8')
      end
      private_class_method :read_cstring

      # Safari stores a leading dot for subdomain matches (.google.com).
      # Treat "google.com" and ".google.com" as the same for lookup purposes.
      def self.domain_matches?(cookie_url, wanted)
        stripped = ->(s) { s.sub(/^\./, '') }
        stripped.call(cookie_url) == stripped.call(wanted)
      end
      private_class_method :domain_matches?
    end
  end
end
