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
      DEFAULT_PATH = File.expand_path('~/Library/Cookies/Cookies.binarycookies').freeze

      class ParseError < StandardError; end

      # Raised when this machine cannot supply Safari cookies at all — a
      # non-macOS host, or a Mac where Safari has never stored any. Distinct
      # from ParseError, which means the file exists but is not what we expect.
      class Unavailable < StandardError; end

      def self.available?
        RbConfig::CONFIG['host_os'].to_s.match?(/darwin/) && File.exist?(DEFAULT_PATH)
      end

      def self.read(domain:, names: nil, path: DEFAULT_PATH)
        unless RbConfig::CONFIG['host_os'].to_s.match?(/darwin/)
          raise Unavailable,
                'Google Voice support reads Safari session cookies and therefore ' \
                'only works on macOS. This host is not macOS.'
        end
        unless File.exist?(path)
          raise Unavailable,
                "No Safari cookie store at #{path}. Sign in to Google in Safari on this machine first."
        end

        data = File.binread(path)
        raise ParseError, "Bad magic in #{path}" unless data[0, 4] == 'cook'

        num_pages = data[4, 4].unpack1('L>')
        page_sizes = data[8, num_pages * 4].unpack("L>#{num_pages}")

        pages = []
        offset = 8 + num_pages * 4
        page_sizes.each do |size|
          pages << data[offset, size]
          offset += size
        end

        result = {}
        pages.each do |page|
          parse_page(page) do |cookie|
            next unless domain_matches?(cookie[:url], domain)
            next if names && !names.include?(cookie[:name])
            result[cookie[:name]] = cookie[:value]
          end
        end
        result
      end

      def self.parse_page(page)
        num_cookies = page[4, 4].unpack1('L<')
        cookie_offsets = page[8, num_cookies * 4].unpack("L<#{num_cookies}")
        cookie_offsets.each do |co|
          rec = page[co..]
          size = rec[0, 4].unpack1('L<')
          rec = rec[0, size]
          url_off   = rec[16, 4].unpack1('L<')
          name_off  = rec[20, 4].unpack1('L<')
          path_off  = rec[24, 4].unpack1('L<')
          value_off = rec[28, 4].unpack1('L<')
          yield(
            url:   read_cstring(rec, url_off),
            name:  read_cstring(rec, name_off),
            path:  read_cstring(rec, path_off),
            value: read_cstring(rec, value_off)
          )
        end
      end
      private_class_method :parse_page

      def self.read_cstring(buf, offset)
        terminator = buf.index("\x00".b, offset) || buf.bytesize
        buf[offset...terminator].force_encoding('UTF-8')
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
