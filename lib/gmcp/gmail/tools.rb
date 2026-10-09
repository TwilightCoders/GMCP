require 'mcp'

module GMCP
  module Gmail
    module Tools
      def self.register(server)
        register_read(server)
        register_write(server)
        register_bulk(server)
        register_attachments(server)
        register_unsubscribe(server)
      end

      def self.register_read(server)
        ToolHelpers.account_tool(
          server,
          name: 'gmail_search',
          capability: 'gmail.read',
          description: 'Search Gmail messages using a query string (same syntax as Gmail search box). ' \
                       'Returns a page_token when more results exist; pass it back to get the next page.',
          properties: {
            query:       { type: 'string', description: 'Gmail search query, e.g. "from:alice subject:report"' },
            max_results: { type: 'integer', description: 'Max messages per page (default 20, Gmail caps at 500)' },
            page_token:  { type: 'string', description: 'Cursor from a previous call. Omit for the first page.' }
          },
          required: ['query']
        ) do |query:, max_results: 20, page_token: nil|
          page = Message.search_page(query, max_results: max_results, page_token: page_token)
          lines = page[:messages].map { |m| m.id.to_s }
          body  = lines.empty? ? 'No messages found.' : lines.join("\n")
          if page[:next_page_token]
            body += "\n\nMore results available. next page_token: #{page[:next_page_token]}"
          end
          body += "\n(Gmail estimates ~#{page[:estimate]} total matches; the estimate is approximate.)" if page[:estimate]
          ToolHelpers.text_response(body)
        end

        ToolHelpers.account_tool(
          server,
          name: 'gmail_get_message',
          capability: 'gmail.read',
          description: 'Get a Gmail message by ID, with decoded headers and body text',
          properties: {
            message_id: { type: 'string' }
          },
          required: ['message_id']
        ) do |message_id:|
          ToolHelpers.json_response(Message.find(message_id).to_summary)
        end

        ToolHelpers.account_tool(
          server,
          name: 'gmail_list_labels',
          capability: 'gmail.read',
          description: 'List all Gmail labels',
          properties: {}
        ) do
          ToolHelpers.list_response(Label.all, empty_message: 'No labels found.') { |l| "#{l.id}: #{l.name}" }
        end
      end

      def self.register_write(server)
        ToolHelpers.account_tool(
          server,
          name: 'gmail_trash_message',
          capability: 'gmail.trash',
          description: 'Move a Gmail message to trash',
          properties: {
            message_id: { type: 'string' }
          },
          required: ['message_id']
        ) do |message_id:|
          Message.find(message_id).trash!
          ToolHelpers.text_response("Message #{message_id} moved to trash.")
        end

        ToolHelpers.account_tool(
          server,
          name: 'gmail_archive_message',
          capability: 'gmail.modify_labels',
          description: 'Archive a Gmail message (remove from INBOX)',
          properties: {
            message_id: { type: 'string' }
          },
          required: ['message_id']
        ) do |message_id:|
          Message.find(message_id).archive!
          ToolHelpers.text_response("Message #{message_id} archived.")
        end

        ToolHelpers.account_tool(
          server,
          name: 'gmail_label_message',
          capability: 'gmail.modify_labels',
          description: 'Add and/or remove labels on a Gmail message',
          properties: {
            message_id:       { type: 'string' },
            add_label_ids:    { type: 'array', items: { type: 'string' }, description: 'Label IDs to add' },
            remove_label_ids: { type: 'array', items: { type: 'string' }, description: 'Label IDs to remove' }
          },
          required: ['message_id']
        ) do |message_id:, add_label_ids: [], remove_label_ids: []|
          Message.find(message_id).modify!(addLabelIds: add_label_ids, removeLabelIds: remove_label_ids)
          ToolHelpers.text_response("Labels updated on #{message_id}.")
        end

        ToolHelpers.account_tool(
          server,
          name: 'gmail_send',
          capability: 'gmail.send',
          description: 'Send a new email',
          properties: {
            to:      { type: 'string', description: 'Recipient email address' },
            subject: { type: 'string' },
            body:    { type: 'string', description: 'Plain-text message body' }
          },
          required: ['to', 'subject', 'body']
        ) do |to:, subject:, body:|
          Message.send_message(to: to, subject: subject, body: body)
          ToolHelpers.text_response("Message sent to #{to}.")
        end

        ToolHelpers.account_tool(
          server,
          name: 'gmail_create_draft',
          capability: 'gmail.send',
          description: 'Create a Gmail draft',
          properties: {
            to:      { type: 'string' },
            subject: { type: 'string' },
            body:    { type: 'string' }
          },
          required: ['to', 'subject', 'body']
        ) do |to:, subject:, body:|
          Draft.create_draft(to: to, subject: subject, body: body)
          ToolHelpers.text_response('Draft created.')
        end

        ToolHelpers.account_tool(
          server,
          name: 'gmail_reply',
          capability: 'gmail.send',
          description: 'Reply to a Gmail message',
          properties: {
            message_id: { type: 'string' },
            body:       { type: 'string', description: 'Reply body (plain text)' }
          },
          required: ['message_id', 'body']
        ) do |message_id:, body:|
          Message.metadata(message_id, headers: Message::REPLY_HEADERS).reply!(body: body)
          ToolHelpers.text_response('Reply sent.')
        end
      end

      # ── bulk operations ─────────────────────────────────────────────────
      #
      # One request for up to 1000 messages. Without these, acting on a
      # triage result means one round trip per message.
      def self.register_bulk(server)
        ToolHelpers.account_tool(
          server,
          name: 'gmail_batch_archive',
          capability: 'gmail.modify_labels',
          description: 'Archive many messages at once (removes INBOX). Up to 1000 ids per call. Reversible.',
          properties: {
            message_ids: { type: 'array', items: { type: 'string' }, description: 'Message IDs to archive' }
          },
          required: ['message_ids']
        ) do |message_ids:|
          Tools.batching(message_ids) do |ids|
            Message.batch_archive(ids: ids)
            "Archived #{ids.length} message(s)."
          end
        end

        ToolHelpers.account_tool(
          server,
          name: 'gmail_batch_trash',
          capability: 'gmail.trash',
          description: 'Move many messages to trash at once. Up to 1000 ids per call. ' \
                       'Recoverable for 30 days, after which Gmail deletes them permanently.',
          properties: {
            message_ids: { type: 'array', items: { type: 'string' }, description: 'Message IDs to trash' }
          },
          required: ['message_ids']
        ) do |message_ids:|
          Tools.batching(message_ids) do |ids|
            Message.batch_trash(ids: ids)
            "Moved #{ids.length} message(s) to trash. Recoverable for 30 days."
          end
        end

        ToolHelpers.account_tool(
          server,
          name: 'gmail_batch_modify',
          capability: 'gmail.modify_labels',
          description: 'Add and/or remove labels on many messages at once. Up to 1000 ids per call.',
          properties: {
            message_ids:      { type: 'array', items: { type: 'string' } },
            add_label_ids:    { type: 'array', items: { type: 'string' }, description: 'Label IDs to add' },
            remove_label_ids: { type: 'array', items: { type: 'string' }, description: 'Label IDs to remove' }
          },
          required: ['message_ids']
        ) do |message_ids:, add_label_ids: [], remove_label_ids: []|
          if add_label_ids.empty? && remove_label_ids.empty?
            next ToolHelpers.text_response('Nothing to do: no labels to add or remove.')
          end
          Tools.batching(message_ids) do |ids|
            Message.batch_modify(ids: ids, add_label_ids: add_label_ids, remove_label_ids: remove_label_ids)
            "Updated labels on #{ids.length} message(s)."
          end
        end
      end

      # ── attachments ─────────────────────────────────────────────────────
      def self.register_attachments(server)
        ToolHelpers.account_tool(
          server,
          name: 'gmail_list_attachments',
          capability: 'gmail.read',
          description: 'List the attachments on a message (filename, type, size, and the id needed to download it).',
          properties: {
            message_id: { type: 'string' }
          },
          required: ['message_id']
        ) do |message_id:|
          found = Message.attachments(message_id)
          ToolHelpers.list_response(found, empty_message: 'No attachments on this message.') do |a|
            "#{a[:attachment_id]}  #{a[:filename]}  (#{a[:mime_type]}, #{a[:size]} bytes)"
          end
        end

        ToolHelpers.account_tool(
          server,
          name: 'gmail_download_attachment',
          capability: 'gmail.download',
          description: 'Download an attachment to a local directory. Get the attachment_id from gmail_list_attachments.',
          properties: {
            message_id:    { type: 'string' },
            attachment_id: { type: 'string' },
            dest_dir:      { type: 'string', description: 'Existing directory to write into. Required — there is no default.' },
            filename:      { type: 'string', description: 'Override the filename. Defaults to the name on the attachment.' }
          },
          required: %w[message_id attachment_id dest_dir]
        ) do |message_id:, attachment_id:, dest_dir:, filename: nil|
          Tools.download_attachment_to(
            message_id: message_id, attachment_id: attachment_id,
            dest_dir: dest_dir, filename: filename
          )
        end
      end

      # ── unsubscribe ─────────────────────────────────────────────────────
      def self.register_unsubscribe(server)
        ToolHelpers.account_tool(
          server,
          name: 'gmail_unsubscribe_info',
          capability: 'gmail.read',
          description: 'Show the List-Unsubscribe options a message offers, and whether one-click (RFC 8058) is supported.',
          properties: {
            message_id: { type: 'string' }
          },
          required: ['message_id']
        ) do |message_id:|
          details = Unsubscribe.info(message_id)
          next ToolHelpers.text_response('This message offers no List-Unsubscribe header.') if details.nil?

          ToolHelpers.text_response([
            "one-click (RFC 8058): #{details[:one_click] ? 'yes' : 'no'}",
            "https:  #{details[:https] || '(none)'}",
            "http:   #{details[:http] || '(none)'}",
            "mailto: #{details[:mailto] || '(none)'}"
          ].join("\n"))
        end

        ToolHelpers.account_tool(
          server,
          name: 'gmail_unsubscribe',
          capability: 'gmail.unsubscribe',
          description: 'Unsubscribe from a sender via RFC 8058 one-click, using the URL in the message\'s own ' \
                       'List-Unsubscribe header. https only. Note this confirms to the sender that the address is live.',
          properties: {
            message_id: { type: 'string', description: 'A message from the sender you want to stop hearing from' }
          },
          required: ['message_id']
        ) do |message_id:|
          begin
            code = Unsubscribe.one_click!(message_id)
            ToolHelpers.text_response("Unsubscribe request accepted (HTTP #{code}).")
          rescue Unsubscribe::NotSupported => e
            ToolHelpers.text_response("Cannot one-click unsubscribe: #{e.message}")
          rescue Unsubscribe::Failed => e
            ToolHelpers.text_response("Unsubscribe failed: #{e.message}")
          rescue StandardError => e
            ToolHelpers.text_response("Unsubscribe error: #{e.class}: #{e.message}")
          end
        end
      end

      class << self
        # Shared shape for the batch tools: reject an empty set, surface
        # Gmail's own limit rather than truncating, and report failures as
        # readable text instead of an MCP internal error.
        def batching(ids)
          ids = Array(ids).map { |i| i.to_s.strip }.reject(&:empty?).uniq
          return ToolHelpers.text_response('No message ids given.') if ids.empty?

          ToolHelpers.text_response(yield(ids))
        rescue ArgumentError => e
          ToolHelpers.text_response("Refused: #{e.message}")
        rescue StandardError => e
          ToolHelpers.text_response("Batch failed: #{e.class}: #{e.message}")
        end

        def download_attachment_to(message_id:, attachment_id:, dest_dir:, filename: nil)
          dir = ::File.expand_path(dest_dir)
          return ToolHelpers.text_response("Not a directory: #{dir}") unless ::File.directory?(dir)

          name = ::File.basename((filename || default_attachment_name(message_id, attachment_id)).to_s)
          return ToolHelpers.text_response('Refusing to write: unusable filename.') if name.empty? || name == '.' || name == '..'

          path = ::File.expand_path(::File.join(dir, name))
          # basename should make this unreachable; belt and braces against a
          # filename that escapes the destination.
          unless path.start_with?(dir + ::File::SEPARATOR)
            return ToolHelpers.text_response('Refusing to write outside the destination directory.')
          end
          return ToolHelpers.text_response("Refusing to overwrite existing file: #{path}") if ::File.exist?(path)

          bytes = Message.download_attachment(message_id: message_id, attachment_id: attachment_id)
          ::File.binwrite(path, bytes)
          ToolHelpers.text_response("Wrote #{bytes.bytesize} bytes to #{path}")
        rescue StandardError => e
          ToolHelpers.text_response("Download failed: #{e.class}: #{e.message}")
        end

        private

        def default_attachment_name(message_id, attachment_id)
          match = Message.attachments(message_id).find { |a| a[:attachment_id] == attachment_id }
          match ? match[:filename] : "#{message_id}-#{attachment_id[0, 12]}.bin"
        end
      end
    end
  end
end
