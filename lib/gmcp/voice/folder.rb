# frozen_string_literal: true

module GMCP
  module Voice
    # One page of threads from api2thread/list, the endpoint voice.google.com
    # itself uses. The request is positional:
    #
    #   [folder_id, threads_per_page, messages_per_thread, cursor, _, [_, 1, 1, 1]]
    #
    # The trailing array is what the web client always sends. The cursor is the
    # newest-message timestamp (ms, as a string) of the last thread on the
    # previous page; nil asks for the most recent page.
    #
    # The response is [threads, _, version_token].
    class Folder
      PAGE_SIZE           = 20
      MESSAGES_PER_THREAD = 15
      SEARCH_PAGES        = 10
      MAX_SEARCH_PAGES    = 50

      attr_reader :name, :conversations

      def self.fetch(session, name = 'all', cursor: nil)
        id = FOLDERS.fetch(name.to_s) do
          raise ArgumentError, "Unknown folder: #{name}. Valid: #{FOLDERS.keys.join(', ')}"
        end
        body = [id, PAGE_SIZE, MESSAGES_PER_THREAD, cursor&.to_s, nil, [nil, 1, 1, 1]]
        new(name.to_s, session.call('api2thread/list', body))
      end

      # The API has no server-side search we can call, so walk recent pages
      # and match locally. Bounded, because the call log reaches back years
      # and each page is a round trip.
      def self.search(session, query, folder: 'all', pages: SEARCH_PAGES)
        pages = pages.to_i.clamp(1, MAX_SEARCH_PAGES)
        matches = []
        scanned = 0
        cursor = nil
        pages.times do
          page = fetch(session, folder, cursor: cursor)
          scanned += page.conversations.size
          matches.concat(page.conversations.select { |c| c.matches?(query) })
          following = page.next_cursor
          break if following.nil? || following == cursor

          cursor = following
        end
        [matches, scanned]
      end

      def initialize(name, response)
        @name = name
        rows = response.is_a?(Array) && response[0].is_a?(Array) ? response[0] : []
        @conversations = rows.filter_map { |row| Conversation.from_jspb(row) }
      end

      # Cursor for the page after this one, or nil when this page was empty.
      def next_cursor
        @conversations.last&.latest&.timestamp_ms&.to_s
      end

      def inspect
        "#<Voice::Folder #{@name} (#{@conversations.size} threads)>"
      end
    end
  end
end
