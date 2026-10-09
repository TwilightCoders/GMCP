# frozen_string_literal: true

module GMCP
  module Voice
    # A Voice thread: one counterparty's texts, or a call/voicemail record.
    # Decoded from the positional array api2thread/list returns:
    #
    #   [id, read, messages, pagination_token, contacts, folders, _, is_text,
    #    phone_numbers]
    #
    # Messages come newest first. Text thread ids look like "t.+<number>",
    # call and voicemail ids like "c.<opaque>".
    #
    # Named Conversation rather than Thread so it never shadows ::Thread
    # inside this namespace.
    class Conversation
      attr_reader :id, :messages, :phone_numbers, :names

      def self.from_jspb(row)
        return nil unless row.is_a?(Array) && row[0].is_a?(String)

        new(row)
      end

      def initialize(row)
        @id       = row[0]
        @read     = row[1] == true
        @messages = Array(row[2]).filter_map { |m| Message.from_jspb(m) }

        contacts = Array(row[4]).map { |c| Message.split_contact(c) }
        contacts += @messages.map { |m| [m.name, m.phone_number] }
        @names         = contacts.map(&:first).compact.uniq
        @phone_numbers = (Array(row[8]).grep(String) + contacts.map(&:last)).compact.uniq
      end

      def read?
        @read
      end

      def latest
        @messages.first
      end

      def counterparty
        [@names.first, @phone_numbers.first].compact.join(' ').then { |s| s.empty? ? @id : s }
      end

      # Case-insensitive substring match over names, numbers and message text.
      # A query that is mostly digits also matches on digits alone, so
      # "555-0100" finds "+15550100".
      def matches?(query)
        needle = query.to_s.downcase.strip
        return false if needle.empty?

        haystack = [*@names, *@phone_numbers, *@messages.map(&:text)].compact
        return true if haystack.any? { |s| s.downcase.include?(needle) }

        digits = needle.gsub(/\D/, '')
        return false if digits.length < 3 || needle.match?(/[a-z]/)

        @phone_numbers.any? { |p| p.gsub(/\D/, '').include?(digits) }
      end
    end
  end
end
