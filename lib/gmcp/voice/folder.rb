# frozen_string_literal: true

require 'json'

module GMCP
  module Voice
    class Folder
      class ParseError < StandardError; end

      # The feeds return XML with embedded JSON inside a <json> tag.
      JSON_TAG_PATTERN = %r{<json[^>]*>(.*?)</json>}m.freeze
      CDATA_PATTERN    = /\A<!\[CDATA\[(.*)\]\]>\z/m.freeze

      attr_reader :name, :total_size, :unread_counts, :results_per_page

      def self.fetch(session, feed_name)
        url = FEED_URLS.fetch(feed_name.to_sym) { raise ArgumentError, "Unknown feed: #{feed_name}. Valid: #{FEEDS.join(', ')}" }
        resp = session.get(url)
        raise "Feed request failed (#{resp.code})" unless resp.is_a?(Net::HTTPSuccess)
        new(session, feed_name, resp.body)
      end

      def self.search(session, query)
        resp = session.get(SEARCH_URL, params: { q: query })
        raise "Search request failed (#{resp.code})" unless resp.is_a?(Net::HTTPSuccess)
        new(session, 'search', resp.body)
      end

      def initialize(session, name, body)
        @session = session
        @name    = name
        @data    = parse_feed(body)

        @total_size      = @data['totalSize']
        @results_per_page = @data['resultsPerPage']
        @unread_counts   = @data['unreadCounts'] || {}
      end

      def messages
        (@data['messages'] || {}).map { |id, attrs| Message.new(@session, id, attrs) }
      end

      def size
        @total_size.to_i
      end

      def inspect
        "#<Voice::Folder #{@name} (#{size} messages)>"
      end

      private

      def parse_feed(body)
        match = JSON_TAG_PATTERN.match(body) or raise ParseError, 'No <json> section in feed response'
        raw = match[1].strip
        raw = CDATA_PATTERN.match(raw)&.captures&.first&.strip || raw
        JSON.parse(raw)
      rescue JSON::ParserError => e
        raise ParseError, "Feed JSON parse error: #{e.message}"
      end
    end
  end
end
