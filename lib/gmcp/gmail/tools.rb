require 'mcp'

module GMCP
  module Gmail
    module Tools
      def self.register(server)
        register_read(server)
        register_write(server)
      end

      def self.register_read(server)
        server.define_tool(
          name: 'gmail_search',
          description: 'Search Gmail messages using a query string (same syntax as Gmail search box)',
          input_schema: {
            properties: {
              query:       { type: 'string', description: 'Gmail search query, e.g. "from:alice subject:report"' },
              max_results: { type: 'integer', description: 'Max messages to return (default 20)' }
            },
            required: ['query']
          }
        ) do |query:, max_results: 20|
          messages = Message.search(query, max_results: max_results)
          text = messages.map { |m| "#{m.id} — #{m.snippet}" }.join("\n")
          MCP::Tool::Response.new([{ type: 'text', text: text.empty? ? 'No messages found.' : text }])
        end

        server.define_tool(
          name: 'gmail_get_message',
          description: 'Get a Gmail message by ID',
          input_schema: {
            properties: { message_id: { type: 'string' } },
            required: ['message_id']
          }
        ) do |message_id:|
          msg = Message.find(message_id)
          MCP::Tool::Response.new([{ type: 'text', text: msg.to_json }])
        end

        server.define_tool(
          name: 'gmail_list_labels',
          description: 'List all Gmail labels',
          input_schema: { properties: {}, required: [] }
        ) do
          labels = Label.all
          text = labels.map { |l| "#{l.id}: #{l.name}" }.join("\n")
          MCP::Tool::Response.new([{ type: 'text', text: text }])
        end
      end

      def self.register_write(server)
        server.define_tool(
          name: 'gmail_trash_message',
          description: 'Move a Gmail message to trash',
          input_schema: {
            properties: { message_id: { type: 'string' } },
            required: ['message_id']
          }
        ) do |message_id:|
          Message.find(message_id).trash!
          MCP::Tool::Response.new([{ type: 'text', text: "Message #{message_id} moved to trash." }])
        end

        server.define_tool(
          name: 'gmail_archive_message',
          description: 'Archive a Gmail message (remove from INBOX)',
          input_schema: {
            properties: { message_id: { type: 'string' } },
            required: ['message_id']
          }
        ) do |message_id:|
          Message.find(message_id).archive!
          MCP::Tool::Response.new([{ type: 'text', text: "Message #{message_id} archived." }])
        end

        server.define_tool(
          name: 'gmail_label_message',
          description: 'Add and/or remove labels on a Gmail message',
          input_schema: {
            properties: {
              message_id:        { type: 'string' },
              add_label_ids:     { type: 'array', items: { type: 'string' }, description: 'Label IDs to add' },
              remove_label_ids:  { type: 'array', items: { type: 'string' }, description: 'Label IDs to remove' }
            },
            required: ['message_id']
          }
        ) do |message_id:, add_label_ids: [], remove_label_ids: []|
          Message.find(message_id).modify!(add_label_ids: add_label_ids, remove_label_ids: remove_label_ids)
          MCP::Tool::Response.new([{ type: 'text', text: "Labels updated on #{message_id}." }])
        end

        server.define_tool(
          name: 'gmail_send',
          description: 'Send a new email',
          input_schema: {
            properties: {
              to:      { type: 'string', description: 'Recipient email address' },
              subject: { type: 'string' },
              body:    { type: 'string', description: 'Plain-text message body' }
            },
            required: ['to', 'subject', 'body']
          }
        ) do |to:, subject:, body:|
          Message.send_message(to: to, subject: subject, body: body)
          MCP::Tool::Response.new([{ type: 'text', text: "Message sent to #{to}." }])
        end

        server.define_tool(
          name: 'gmail_create_draft',
          description: 'Create a Gmail draft',
          input_schema: {
            properties: {
              to:      { type: 'string' },
              subject: { type: 'string' },
              body:    { type: 'string' }
            },
            required: ['to', 'subject', 'body']
          }
        ) do |to:, subject:, body:|
          Draft.create_draft(to: to, subject: subject, body: body)
          MCP::Tool::Response.new([{ type: 'text', text: "Draft created." }])
        end

        server.define_tool(
          name: 'gmail_reply',
          description: 'Reply to a Gmail message',
          input_schema: {
            properties: {
              message_id: { type: 'string' },
              body:       { type: 'string', description: 'Reply body (plain text)' }
            },
            required: ['message_id', 'body']
          }
        ) do |message_id:, body:|
          Message.find(message_id).reply!(body: body)
          MCP::Tool::Response.new([{ type: 'text', text: "Reply sent." }])
        end
      end
    end
  end
end
