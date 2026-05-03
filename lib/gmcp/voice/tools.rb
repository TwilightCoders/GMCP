# frozen_string_literal: true

require 'mcp'

module GMCP
  module Voice
    module Tools
      def self.register(server)
        register_read(server)
        register_write(server)
      end

      def self.register_read(server)
        ToolHelpers.define_tool(
          server,
          name: 'voice_list',
          description: "List Google Voice messages from a folder. Folders: #{FEEDS.join(', ')}",
          properties: {
            folder: { type: 'string', description: "Folder name (default: inbox)" },
            **ToolHelpers::ACCOUNT_PARAM
          }
        ) do |folder: 'inbox', account: nil|
          GMCP::Server.with_account(account) do
            session = Tools.session_for(account || GMCP::Server.default_account)
            f = Folder.fetch(session, folder)
            ToolHelpers.list_response(f.messages, empty_message: "No messages in #{folder}.") do |m|
              "#{m.id} [#{m.type_name}] #{m.displayNumber} #{m.displayStartDateTime} read=#{m.isRead}"
            end
          end
        rescue Session::AuthError => e
          ToolHelpers.text_response("Voice auth failed: #{e.message}")
        end

        ToolHelpers.define_tool(
          server,
          name: 'voice_search',
          description: 'Search Google Voice call/SMS/voicemail history',
          properties: {
            query: { type: 'string', description: 'Search query' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['query']
        ) do |query:, account: nil|
          GMCP::Server.with_account(account) do
            session = Tools.session_for(account || GMCP::Server.default_account)
            f = Folder.search(session, query)
            ToolHelpers.list_response(f.messages, empty_message: 'No results.') do |m|
              "#{m.id} [#{m.type_name}] #{m.displayNumber} #{m.displayStartDateTime}"
            end
          end
        rescue Session::AuthError => e
          ToolHelpers.text_response("Voice auth failed: #{e.message}")
        end
      end

      def self.register_write(server)
        ToolHelpers.define_tool(
          server,
          name: 'voice_delete',
          description: 'Move a Google Voice message to trash',
          properties: {
            message_id: { type: 'string' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['message_id']
        ) do |message_id:, account: nil|
          GMCP::Server.with_account(account) do
            session = Tools.session_for(account || GMCP::Server.default_account)
            Message.new(session, message_id, {}).delete!
            ToolHelpers.text_response("Message #{message_id} moved to trash.")
          end
        rescue Session::AuthError, Session::OperationError => e
          ToolHelpers.text_response("Voice error: #{e.message}")
        end

        ToolHelpers.define_tool(
          server,
          name: 'voice_archive',
          description: 'Archive a Google Voice message (remove from inbox)',
          properties: {
            message_id: { type: 'string' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['message_id']
        ) do |message_id:, account: nil|
          GMCP::Server.with_account(account) do
            session = Tools.session_for(account || GMCP::Server.default_account)
            Message.new(session, message_id, {}).archive!
            ToolHelpers.text_response("Message #{message_id} archived.")
          end
        rescue Session::AuthError, Session::OperationError => e
          ToolHelpers.text_response("Voice error: #{e.message}")
        end

        ToolHelpers.define_tool(
          server,
          name: 'voice_mark_read',
          description: 'Mark a Google Voice message as read or unread',
          properties: {
            message_id: { type: 'string' },
            read:        { type: 'boolean', description: 'true = mark read, false = mark unread (default: true)' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['message_id']
        ) do |message_id:, read: true, account: nil|
          GMCP::Server.with_account(account) do
            session = Tools.session_for(account || GMCP::Server.default_account)
            Message.new(session, message_id, {}).mark_read!(read: read)
            ToolHelpers.text_response("Message #{message_id} marked #{read ? 'read' : 'unread'}.")
          end
        rescue Session::AuthError, Session::OperationError => e
          ToolHelpers.text_response("Voice error: #{e.message}")
        end
      end

      # Cache sessions per account so cookies and _rnr_se are reused across tool calls.
      def self.session_for(account)
        @sessions ||= {}
        @sessions[account] ||= Session.new(GMCP::Auth.access_token(account: account))
      end
    end
  end
end
