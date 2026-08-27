require 'mcp'

module GMCP
  module Gmail
    module Tools
      def self.register(server)
        register_read(server)
        register_write(server)
      end

      def self.register_read(server)
        ToolHelpers.define_tool(
          server,
          name: 'gmail_search',
          capability: 'gmail.read',
          description: 'Search Gmail messages using a query string (same syntax as Gmail search box)',
          properties: {
            query:       { type: 'string', description: 'Gmail search query, e.g. "from:alice subject:report"' },
            max_results: { type: 'integer', description: 'Max messages to return (default 20)' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['query']
        ) do |query:, max_results: 20, account: nil|
          GMCP::Server.with_account(account) do
            messages = Message.search(query, max_results: max_results)
            ToolHelpers.list_response(messages, empty_message: 'No messages found.') { |m| "#{m.id} — #{m.snippet}" }
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'gmail_get_message',
          capability: 'gmail.read',
          description: 'Get a Gmail message by ID',
          properties: {
            message_id: { type: 'string' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['message_id']
        ) do |message_id:, account: nil|
          GMCP::Server.with_account(account) do
            ToolHelpers.json_response(Message.find(message_id))
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'gmail_list_labels',
          capability: 'gmail.read',
          description: 'List all Gmail labels',
          properties: { **ToolHelpers::ACCOUNT_PARAM }
        ) do |account: nil|
          GMCP::Server.with_account(account) do
            ToolHelpers.list_response(Label.all, empty_message: 'No labels found.') { |l| "#{l.id}: #{l.name}" }
          end
        end
      end

      def self.register_write(server)
        ToolHelpers.define_tool(
          server,
          name: 'gmail_trash_message',
          capability: 'gmail.trash',
          description: 'Move a Gmail message to trash',
          properties: {
            message_id: { type: 'string' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['message_id']
        ) do |message_id:, account: nil|
          GMCP::Server.with_account(account) do
            Message.find(message_id).trash!
            ToolHelpers.text_response("Message #{message_id} moved to trash.")
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'gmail_archive_message',
          capability: 'gmail.modify',
          description: 'Archive a Gmail message (remove from INBOX)',
          properties: {
            message_id: { type: 'string' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['message_id']
        ) do |message_id:, account: nil|
          GMCP::Server.with_account(account) do
            Message.find(message_id).archive!
            ToolHelpers.text_response("Message #{message_id} archived.")
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'gmail_label_message',
          capability: 'gmail.modify',
          description: 'Add and/or remove labels on a Gmail message',
          properties: {
            message_id:       { type: 'string' },
            add_label_ids:    { type: 'array', items: { type: 'string' }, description: 'Label IDs to add' },
            remove_label_ids: { type: 'array', items: { type: 'string' }, description: 'Label IDs to remove' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['message_id']
        ) do |message_id:, add_label_ids: [], remove_label_ids: [], account: nil|
          GMCP::Server.with_account(account) do
            Message.find(message_id).modify!(addLabelIds: add_label_ids, removeLabelIds: remove_label_ids)
            ToolHelpers.text_response("Labels updated on #{message_id}.")
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'gmail_send',
          capability: 'gmail.send',
          description: 'Send a new email',
          properties: {
            to:      { type: 'string', description: 'Recipient email address' },
            subject: { type: 'string' },
            body:    { type: 'string', description: 'Plain-text message body' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['to', 'subject', 'body']
        ) do |to:, subject:, body:, account: nil|
          GMCP::Server.with_account(account) do
            Message.send_message(to: to, subject: subject, body: body)
            ToolHelpers.text_response("Message sent to #{to}.")
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'gmail_create_draft',
          capability: 'gmail.send',
          description: 'Create a Gmail draft',
          properties: {
            to:      { type: 'string' },
            subject: { type: 'string' },
            body:    { type: 'string' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['to', 'subject', 'body']
        ) do |to:, subject:, body:, account: nil|
          GMCP::Server.with_account(account) do
            Draft.create_draft(to: to, subject: subject, body: body)
            ToolHelpers.text_response('Draft created.')
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'gmail_reply',
          capability: 'gmail.send',
          description: 'Reply to a Gmail message',
          properties: {
            message_id: { type: 'string' },
            body:       { type: 'string', description: 'Reply body (plain text)' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['message_id', 'body']
        ) do |message_id:, body:, account: nil|
          GMCP::Server.with_account(account) do
            Message.find(message_id).reply!(body: body)
            ToolHelpers.text_response('Reply sent.')
          end
        end
      end
    end
  end
end
