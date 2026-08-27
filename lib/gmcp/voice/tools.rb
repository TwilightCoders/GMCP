# frozen_string_literal: true

require 'mcp'

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
          description: "List Google Voice messages from a folder. Folders: #{FEEDS.join(', ')}",
          properties: {
            folder: { type: 'string', description: 'Folder name (default: inbox)' }
          }
        ) do |folder: 'inbox'|
          Tools.guarding do
            f = Folder.fetch(Tools.session, folder)
            ToolHelpers.list_response(f.messages, empty_message: "No messages in #{folder}.") do |m|
              "#{m.id} [#{m.type_name}] #{m.displayNumber} #{m.displayStartDateTime} read=#{m.isRead}"
            end
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'voice_search',
          capability: 'voice.read',
          description: 'Search Google Voice call/SMS/voicemail history',
          properties: {
            query: { type: 'string', description: 'Search query' }
          },
          required: ['query']
        ) do |query:|
          Tools.guarding do
            f = Folder.search(Tools.session, query)
            ToolHelpers.list_response(f.messages, empty_message: 'No results.') do |m|
              "#{m.id} [#{m.type_name}] #{m.displayNumber} #{m.displayStartDateTime}"
            end
          end
        end
      end

      def self.register_write(server)
        ToolHelpers.define_tool(
          server,
          name: 'voice_archive',
          capability: 'voice.modify',
          description: 'Archive a Google Voice message (remove from inbox)',
          properties: {
            message_id: { type: 'string' }
          },
          required: ['message_id']
        ) do |message_id:|
          Tools.guarding do
            Message.new(Tools.session, message_id, {}).archive!
            ToolHelpers.text_response("Message #{message_id} archived.")
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'voice_mark_read',
          capability: 'voice.modify',
          description: 'Mark a single Google Voice message as read or unread',
          properties: {
            message_id: { type: 'string' },
            read:       { type: 'boolean', description: 'true = mark read, false = mark unread (default: true)' }
          },
          required: ['message_id']
        ) do |message_id:, read: true|
          Tools.guarding do
            Message.new(Tools.session, message_id, {}).mark_read!(read: read)
            ToolHelpers.text_response("Message #{message_id} marked #{read ? 'read' : 'unread'}.")
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'voice_delete',
          capability: 'voice.trash',
          description: 'Move a Google Voice message to trash',
          properties: {
            message_id: { type: 'string' }
          },
          required: ['message_id']
        ) do |message_id:|
          Tools.guarding do
            Message.new(Tools.session, message_id, {}).delete!
            ToolHelpers.text_response("Message #{message_id} moved to trash.")
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

        # Test/reauth seam: drop the memoized session so the next call re-reads
        # cookies from disk (e.g. after the user signs in again in Safari).
        def reset_session!
          @session = nil
        end

        # Voice number for the current session, or nil. Shape of account/get is
        # [["+1XXXXXXXXXX", ...]].
        def account_number
          resp = session.call('account/get', [])
          resp.dig(0, 0) if resp.is_a?(Array)
        end

        # Uniform error surface for every voice tool. Cookie problems and API
        # problems both come back as readable text rather than an MCP -32603.
        def guarding
          yield
        rescue Session::AuthError => e
          ToolHelpers.text_response(
            "Voice auth failed: #{e.message}\n" \
            'Sign in to voice.google.com in Safari, then retry.'
          )
        rescue Session::OperationError => e
          ToolHelpers.text_response("Voice API error: #{e.message}")
        end
      end
    end
  end
end
