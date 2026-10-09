# frozen_string_literal: true

module GMCP
  module Voice
    # One call, voicemail, or text inside a Conversation, decoded from the
    # positional (JSPB) array the API returns. Index N holds proto field N+1:
    #
    #   [id, timestamp_ms, destination_id, contact, type, status, transcript,
    #    _, duration_s, text, _, media_url, coarse_type, transcript_status, mms]
    #
    # contact is [name, phone_number]; mms is [text, subject, attachments, ...];
    # transcript is [confidence, [[token_bytes_base64, ...], ...]].
    class Message
      attr_reader :id, :timestamp_ms, :type, :name, :phone_number, :duration, :text

      def self.from_jspb(row)
        return nil unless row.is_a?(Array) && row[0].is_a?(String)

        new(row)
      end

      def initialize(row)
        @id           = row[0]
        @timestamp_ms = integer(row[1])
        @name, @phone_number = Message.split_contact(row[3])
        @type         = integer(row[4])
        @read         = integer(row[5]) == 1
        @duration     = row[8].is_a?(Numeric) ? row[8] : nil
        @text         = present(row[9]) || present(row[14].is_a?(Array) ? row[14][0] : nil) || transcript(row[6])
      end

      def read?
        @read
      end

      def type_name
        MESSAGE_TYPES.fetch(@type, "type#{@type}")
      end

      def time
        Time.at(@timestamp_ms / 1000.0) if @timestamp_ms
      end

      # A contact is [name, phone], but either slot may be empty, so classify
      # by content rather than trusting position for which is the number.
      def self.split_contact(contact)
        strings = Array(contact).grep(String).reject(&:empty?)
        phone = strings.find { |s| s.match?(/\A\+?[\d\s().-]{3,}\z/) }
        [(strings - [phone]).first, phone]
      end

      private

      def integer(value)
        Integer(value)
      rescue ArgumentError, TypeError
        nil
      end

      def present(value)
        value.is_a?(String) && !value.empty? ? value : nil
      end

      # Voicemail transcripts arrive as base64 token bytes. Anything that does
      # not decode to valid UTF-8 is used as-is rather than dropped.
      def transcript(raw)
        tokens = raw.is_a?(Array) && raw[1].is_a?(Array) ? raw[1] : []
        words = tokens.filter_map do |token|
          bytes = token.is_a?(Array) ? token[0] : nil
          next unless bytes.is_a?(String)

          decoded = bytes.unpack1('m0').force_encoding('UTF-8')
          decoded.valid_encoding? ? decoded : bytes
        rescue ArgumentError
          bytes
        end
        words.empty? ? nil : words.join(' ')
      end
    end
  end
end
