# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'digest'

module GMCP
  module Voice
    # Authenticated client for the internal Google Voice JSPB/protojson API.
    #
    # The "public" Google Voice API is what the voice.google.com SPA calls
    # internally at https://clients6.google.com/voice/v1/voiceclient/...
    # Auth is cookie-based (the session cookies Safari already has from
    # regular browser login) plus a SAPISIDHASH triple Authorization header
    # and a public API key embedded in the voice.google.com page source.
    #
    # No OAuth — the Google OAuth2 scope required for the token→cookie
    # exchange (OAuthLogin) is reserved for Chromium and isn't grantable
    # to external clients. So we read cookies directly from Safari.
    class Session
      class AuthError      < StandardError; end
      class OperationError < StandardError; end

      API_HOST = 'https://clients6.google.com'
      API_PATH = '/voice/v1/voiceclient/'
      # Browser API key published in the voice.google.com page source — it is
      # not a secret and identifies Google's own web client, not the user.
      # Overridable because Google can rotate it at any time, and a rotation
      # should not require editing the gem.
      API_KEY  = ENV.fetch('GMCP_VOICE_API_KEY', 'AIzaSyDTYc1N4xiODyrQYK0Kl6g_y279LjYkrBg')
      ORIGIN   = 'https://voice.google.com'

      # Cookies the browser sends to google.com on every request.
      # SAPISID / __Secure-1PAPISID / __Secure-3PAPISID drive the auth hashes;
      # SID / HSID / SSID / NID identify the session.
      SESSION_COOKIE_NAMES = %w[
        SID HSID SSID APISID SAPISID
        __Secure-1PSID __Secure-3PSID
        __Secure-1PAPISID __Secure-3PAPISID
        __Secure-1PSIDCC __Secure-3PSIDCC
        __Secure-1PSIDTS __Secure-3PSIDTS
        NID
      ].freeze

      # The Authorization header Google's internal APIs expect is three
      # space-separated <tag> <ts>_<sha1(ts SP cookie SP origin)> chunks.
      HASH_COOKIES = [
        ['SAPISIDHASH',   'SAPISID'],
        ['SAPISID1PHASH', '__Secure-1PAPISID'],
        ['SAPISID3PHASH', '__Secure-3PAPISID']
      ].freeze

      def initialize(cookies: nil, cookie_path: nil)
        @cookies = cookies || SafariCookies.read(
          domain: '.google.com',
          names: SESSION_COOKIE_NAMES,
          path: cookie_path || SafariCookies::DEFAULT_PATH
        )
        raise AuthError, 'Missing SAPISID cookie — log into Google in Safari first' unless @cookies['SAPISID']
      rescue SafariCookies::Unavailable, SafariCookies::ParseError => e
        # Surface as AuthError so the tool layer reports it as readable text
        # rather than letting it escape as an MCP internal error.
        raise AuthError, e.message
      end

      # Call a Voice API method. `path` is something like "account/get" or
      # "thread/batchupdateattributes". `body` is the JSPB request payload
      # (usually an array, e.g. [] for empty, [[["id1","id2"]]] for a list).
      # Returns the parsed JSON response.
      def call(path, body = [])
        uri = URI("#{API_HOST}#{API_PATH}#{path}?alt=protojson&key=#{API_KEY}")
        req = Net::HTTP::Post.new(uri)
        headers.each { |k, v| req[k] = v }
        req.body = JSON.generate(body)

        resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
        parsed = JSON.parse(resp.body) rescue nil

        unless resp.is_a?(Net::HTTPSuccess)
          msg = parsed&.dig('error', 'message') || resp.body.to_s[0, 300]
          raise OperationError, "#{path}: HTTP #{resp.code} — #{msg}"
        end

        parsed
      end

      private

      def headers
        {
          'Authorization'       => sapisidhash_header,
          'Cookie'              => cookie_header,
          'Content-Type'        => 'application/json+protobuf',
          'Origin'              => ORIGIN,
          'Referer'             => "#{ORIGIN}/",
          'User-Agent'          => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15',
          'X-Goog-AuthUser'     => '0',
          'X-Goog-Encode-Response-If-Executable' => 'base64',
          'X-JavaScript-User-Agent' => 'google-api-javascript-client/1.1.0',
          'X-Requested-With'    => 'XMLHttpRequest'
        }
      end

      def sapisidhash_header
        ts = Time.now.to_i
        HASH_COOKIES.filter_map do |tag, name|
          val = @cookies[name] or next
          "#{tag} #{ts}_#{Digest::SHA1.hexdigest("#{ts} #{val} #{ORIGIN}")}"
        end.join(' ')
      end

      def cookie_header
        @cookies.map { |k, v| "#{k}=#{v}" }.join('; ')
      end
    end
  end
end
