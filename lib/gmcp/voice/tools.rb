# frozen_string_literal: true

require 'mcp'
require 'time'

module GMCP
  module Voice
    # MCP tools for Google Voice.
    #
    # Each takes the same `account:` as the other services and is limited to
    # GMCP_ACCOUNTS, but does not go through Server.with_account: Voice has no
    # OAuth scope, so its session comes from the Chrome profile signed in to
    # the account (see Voice::Chrome).
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
          description: 'Show the Google Voice number of an account.',
          properties: { **ToolHelpers::ACCOUNT_PARAM }
        ) do |account: nil|
          Tools.guarding(account) do |acct|
            number = Tools.account_number(acct)
            ToolHelpers.text_response(
              number ? "Voice number for #{acct}: #{number}"
                     : "#{acct} has no Google Voice number."
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
            cursor: { type: 'string', description: 'next_cursor from a previous voice_list call' },
            **ToolHelpers::ACCOUNT_PARAM
          }
        ) do |folder: 'all', cursor: nil, account: nil|
          Tools.guarding(account) do |acct|
            page = Folder.fetch(Tools.session(acct), folder, cursor: cursor)
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
            pages:  { type: 'integer', description: "Pages to scan (default: #{Folder::SEARCH_PAGES}, max: #{Folder::MAX_SEARCH_PAGES})" },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['query']
        ) do |query:, folder: 'all', pages: Folder::SEARCH_PAGES, account: nil|
          Tools.guarding(account) do |acct|
            matches, scanned = Folder.search(Tools.session(acct), query, folder: folder, pages: pages)
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
            thread_id: { type: 'string' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['thread_id']
        ) do |thread_id:, account: nil|
          Tools.guarding(account) do |acct|
            Tools.session(acct).call('thread/updateattributes', Tools.mark_read_body(thread_id))
            ToolHelpers.text_response("Thread #{thread_id} marked read.")
          end
        end
      end

      class << self
        # One session per account, reused across calls until Google rejects it.
        def session(account)
          lock.synchronize { sessions[account] ||= Session.for(account) }
        end

        # Drop memoized sessions so the next call fetches fresh cookies.
        # guarding calls this for an account on every auth failure.
        def reset_session!(account = nil)
          lock.synchronize { account ? sessions.delete(account) : sessions.clear }
        end

        # Voice number for an account, or nil when the account has no Voice
        # (account/get answers NOT_FOUND). Shape of account/get is
        # [["+1XXXXXXXXXX", ...]].
        def account_number(account)
          resp = session(account).call('account/get', [])
          resp.dig(0, 0) if resp.is_a?(Array)
        rescue Session::OperationError => e
          raise unless e.message.include?('NOT_FOUND')
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

        # Resolves the account against GMCP_ACCOUNTS and gives every voice tool
        # one error surface, with advice the generic ToolHelpers.guarded cannot
        # give. An auth failure also drops that account's session, so a retry
        # re-reads the profile instead of reusing rejected cookies.
        def guarding(account)
          account = GMCP::Server.configured_account(account)
          begin
            yield account
          rescue Session::AuthError => e
            reset_session!(account)
            ToolHelpers.error_response(
              "Voice auth failed for #{account}: #{e.message}\n" \
              "If this persists, open Google Voice in that account's Chrome profile to refresh its session."
            )
          rescue Session::OperationError => e
            ToolHelpers.error_response("Voice API error: #{e.message}")
          end
        end

        private

        def sessions
          @sessions ||= {}
        end

        def lock
          @lock ||= Mutex.new
        end
      end
    end
  end
end
