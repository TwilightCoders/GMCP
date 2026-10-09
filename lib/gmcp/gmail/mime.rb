# frozen_string_literal: true

module GMCP
  module Gmail
    # The one place outgoing mail becomes RFC 5322 text. Send, draft and reply
    # all go through here, so the safety rules are applied once:
    #
    #   * A CR or LF in any header value is refused. Header values come from
    #     the caller (and, for a reply, from whoever sent the original), and a
    #     bare newline would let either inject headers of their own — a Bcc,
    #     say.
    #   * Non-ASCII header text is RFC 2047 encoded. Raw UTF-8 in a Subject
    #     arrives as mojibake in clients that follow the RFC.
    #   * The body is declared UTF-8 and base64 encoded, so its bytes survive
    #     transport whatever they are.
    module Mime
      # Gmail's own `raw` field is base64url of the whole message.
      def self.build(to:, subject:, body:, cc: nil, headers: {})
        fields = { 'To' => to }
        fields['Cc'] = cc unless cc.nil? || cc.to_s.empty?
        fields['Subject'] = subject
        fields.merge!(headers.transform_keys(&:to_s))

        lines = fields.map { |name, value| field(name, value) }
        lines << 'MIME-Version: 1.0'
        lines << 'Content-Type: text/plain; charset=UTF-8'
        lines << 'Content-Transfer-Encoding: base64'

        Base64.urlsafe_encode64("#{lines.join("\r\n")}\r\n\r\n#{encode_body(body)}")
      end

      ADDRESS_FIELDS = %w[to cc bcc from reply-to].freeze

      # Encoded words cap at 75 characters; the =?UTF-8?B? ... ?= wrapper
      # takes 12, leaving 63 for base64, which holds 47 bytes. Rounded down to
      # whole base64 groups.
      MAX_WORD_BYTES = 45

      class << self
        private

        def field(name, value)
          name = name.to_s
          raise ArgumentError, "invalid header name: #{name.inspect}" unless name.match?(/\A[!-9;-~]+\z/)

          value = utf8(value)
          raise ArgumentError, "#{name} header must not contain a line break" if value.match?(/[\r\n]/)

          encoded = ADDRESS_FIELDS.include?(name.downcase) ? encode_addresses(value) : encode_text(value)
          fold("#{name}: #{encoded}")
        end

        # encode is a no-op on a string already tagged UTF-8, hence the scrub.
        def utf8(value)
          value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace).scrub
        end

        # An address cannot be wrapped in an encoded word — the recipient
        # would see the whole field as a display name with no address — so
        # only the display name of each entry is encoded.
        def encode_addresses(value)
          return value if value.ascii_only?

          value.scan(/(?:"[^"]*"|[^,])+/).map do |entry|
            match = entry.strip.match(/\A"?(?<name>.*?)"?\s*<(?<addr>[^>]*)>\z/)
            next entry.strip unless match && !match[:name].ascii_only?

            "#{encoded_words(match[:name]).join(' ')} <#{match[:addr]}>"
          end.join(', ')
        end

        def encode_text(value)
          value.ascii_only? ? value : encoded_words(value).join(' ')
        end

        # Whitespace between adjacent encoded words is dropped on decode, so a
        # value split across several words reassembles exactly.
        def encoded_words(text)
          chunks = text.each_char.each_with_object([+'']) do |char, acc|
            acc << +'' if acc.last.bytesize + char.bytesize > MAX_WORD_BYTES
            acc.last << char
          end
          chunks.map { |chunk| "=?UTF-8?B?#{Base64.strict_encode64(chunk)}?=" }
        end

        # RFC 5322 recommends 78 characters a line. Folding puts a CRLF in
        # front of existing whitespace and nothing else, so unfolding gives
        # back the exact value — which matters for References on a long thread.
        def fold(line)
          return line if line.length <= 78

          line.split(/(?= )/).each_with_object([]) do |token, out|
            if out.empty? || out.last.length + token.length > 78
              out << +token
            else
              out.last << token
            end
          end.join("\r\n")
        end

        # Canonical text/plain line endings are CRLF.
        def encode_body(body)
          Base64.encode64(utf8(body).gsub(/\r?\n/, "\r\n")).gsub("\n", "\r\n")
        end
      end
    end
  end
end
