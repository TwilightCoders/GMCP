# frozen_string_literal: true

require 'mcp'
require 'time'

module GMCP
  module Voice
    # MCP tools for Google Voice.
    #
    # Unlike the Gmail/Calendar/Drive tools, these do NOT take an `account:`
    # parameter and do NOT go through Server.with_account. Voice has no usable
    # OAuth path — the token→cookie exchange (accounts.google.com/OAuthLogin)
    # is reserved for Chromium — so Session authenticates with the browser
    # cookies Safari already holds. That means the identity is fixed: whichever
    # Google account is signed in to Safari, which is not necessarily the
    # account GMCP_ACCOUNTS names.
    #
    # `voice_account` exists to make that visible rather than silent.
    module Tools
      def self.register(server)
        register_read(server)
        register_write(server)
      end

      def self.register_read(server)
        ToolHelpers.define_tool(
          server,
          name: 'voice_account',
          capability: 'voice.read',
          description: 'Show which Google Voice account the current Safari session resolves to. ' \
                       'Voice auth comes from Safari cookies, not from GMCP_ACCOUNTS, so use this ' \
                       'to confirm whose Voice data the other voice_* tools will operate on.',
          properties: {}
        ) do
          Tools.guarding do
            number = Tools.account_number
            ToolHelpers.text_response(
              number ? "Voice number: #{number} (from Safari session cookies)"
                     : 'Authenticated, but no Voice number returned for this account.'
            )
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'voice_list',
          capability: 'voice.read',
          description: 'List Google Voice threads (texts, calls, voicemail), newest first, 20 per page. ' \
                       "Folders: #{FOLDERS.keys.join(', ')}. Pass the returned next_cursor to get the next page.",
          properties: {
            folder: { type: 'string', description: 'Folder name (default: all)' },
            cursor: { type: 'string', description: 'next_cursor from a previous voice_list call' }
          }
        ) do |folder: 'all', cursor: nil|
          Tools.guarding do
            page = Folder.fetch(Tools.session, folder, cursor: cursor)
            lines = page.conversations.map { |c| Tools.format(c) }
            next ToolHelpers.text_response("No threads in #{folder}.") if lines.empty?

            lines << "next_cursor: #{page.next_cursor}"
            ToolHelpers.text_response(lines.join("\n"))
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'voice_search',
          capability: 'voice.read',
          description: 'Search recent Google Voice threads by contact name, phone number, or message text. ' \
                       'Matches locally over the newest pages of a folder (20 threads per page), so older ' \
                       'history is only reached by raising pages or narrowing the folder.',
          properties: {
            query:  { type: 'string', description: 'Text, name, or phone number to look for' },
            folder: { type: 'string', description: "Folder to scan (default: all). One of #{FOLDERS.keys.join(', ')}" },
            pages:  { type: 'integer', description: "Pages to scan (default: #{Folder::SEARCH_PAGES}, max: #{Folder::MAX_SEARCH_PAGES})" }
          },
          required: ['query']
        ) do |query:, folder: 'all', pages: Folder::SEARCH_PAGES|
          Tools.guarding do
            matches, scanned = Folder.search(Tools.session, query, folder: folder, pages: pages)
            ToolHelpers.list_response(matches, empty_message: "No matches in the #{scanned} most recent #{folder} threads.") do |c|
              Tools.format(c)
            end
          end
        end
      end

      def self.register_write(server)
        ToolHelpers.define_tool(
          server,
          name: 'voice_mark_read',
          capability: 'voice.modify',
          description: 'Mark a Google Voice thread as read. Takes a thread id from voice_list or voice_search.',
          properties: {
            thread_id: { type: 'string' }
          },
          required: ['thread_id']
        ) do |thread_id:|
          Tools.guarding do
            Tools.session.call('thread/updateattributes', Tools.mark_read_body(thread_id))
            ToolHelpers.text_response("Thread #{thread_id} marked read.")
          end
        end
      end

      class << self
        # One session per process. Cookies and derived auth are reused across
        # calls; there is nothing to key it by, because Safari holds exactly one
        # Google session for this user.
        def session
          @session ||= Session.new
        end

        # Drop the memoized session so the next call re-reads cookies from disk.
        # guarding calls this on every auth failure.
        def reset_session!
          @session = nil
        end

        # Voice number for the current session, or nil. Shape of account/get is
        # [["+1XXXXXXXXXX", ...]].
        def account_number
          resp = session.call('account/get', [])
          resp.dig(0, 0) if resp.is_a?(Array)
        end

        # thread/updateattributes takes the new attributes, then a second
        # attributes record naming which fields to change, then 1. Only `read`
        # (field 4) is set in both, so nothing else about the thread is touched.
        # Shape taken from a working open-source Voice client, not from probing:
        # mutations are never sent to a live account to discover their format.
        def mark_read_body(thread_id)
          [
            [thread_id, nil, nil, true, nil, nil, nil, nil],
            [nil, nil, nil, true, nil, nil, nil, nil],
            1
          ]
        end

        def format(conversation)
          latest = conversation.latest
          parts = [conversation.id, "[#{latest&.type_name || 'empty'}]", conversation.counterparty]
          parts << latest.time.iso8601 if latest&.time
          parts << "read=#{conversation.read?}"
          preview = latest&.text.to_s.gsub(/\s+/, ' ').strip
          parts << "— #{preview[0, 120]}" unless preview.empty?
          parts.join(' ')
        end

        # Uniform error surface for every voice tool, with Voice-specific advice
        # that the generic ToolHelpers.guarded cannot give. An auth failure also
        # drops the memoized session, so the retry this message asks for picks
        # up whatever cookies Safari holds now instead of the rejected ones.
        def guarding
          yield
        rescue Session::AuthError => e
          reset_session!
          ToolHelpers.error_response(
            "Voice auth failed: #{e.message}\n" \
            'Sign in to voice.google.com in Safari, then retry.'
          )
        rescue Session::OperationError => e
          ToolHelpers.error_response("Voice API error: #{e.message}")
        end
      end
    end
  end
end
