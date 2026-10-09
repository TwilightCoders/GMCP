require 'mcp'

module GMCP
  module Drive
    module Tools
      def self.register(server)
        ToolHelpers.account_tool(
          server,
          name: 'drive_search',
          capability: 'drive.read',
          description: 'Search Google Drive files, including shared drives, using a Drive query string. ' \
                       'Returns a page_token when more results exist; pass it back to get the next page.',
          properties: {
            query:       { type: 'string', description: "Drive query, e.g. \"name contains 'report' and mimeType='application/pdf'\"" },
            max_results: { type: 'integer' },
            page_token:  { type: 'string', description: 'Cursor from a previous call. Omit for the first page.' }
          },
          required: ['query']
        ) do |query:, max_results: 20, page_token: nil|
          page = File.search_page(query, max_results: max_results, page_token: page_token)
          Tools.listing(page, 'No files found.')
        end

        ToolHelpers.account_tool(
          server,
          name: 'drive_list_folder',
          capability: 'drive.read',
          description: 'List files in a Drive folder. ' \
                       'Returns a page_token when more results exist; pass it back to get the next page.',
          properties: {
            folder_id:   { type: 'string', description: 'Drive folder ID or "root"' },
            max_results: { type: 'integer' },
            page_token:  { type: 'string', description: 'Cursor from a previous call. Omit for the first page.' }
          },
          required: ['folder_id']
        ) do |folder_id:, max_results: 50, page_token: nil|
          page = File.list_folder_page(folder_id, max_results: max_results, page_token: page_token)
          Tools.listing(page, 'Folder is empty.')
        end

        ToolHelpers.account_tool(
          server,
          name: 'drive_read_file',
          capability: 'drive.read',
          description: 'Read a Drive file as text. Google Docs and Slides export as plain text, Sheets as CSV ' \
                       '(first sheet only). Other files must be text and at most 1 MB; binaries are refused.',
          properties: {
            file_id: { type: 'string' }
          },
          required: ['file_id']
        ) do |file_id:|
          ToolHelpers.text_response(File.read_text(file_id))
        end
      end

      def self.listing(page, empty_message)
        lines = page[:files].map { |f| "#{f.id}: #{f.name} (#{f.mimeType})" }
        body  = lines.empty? ? empty_message : lines.join("\n")
        body += "\n\nMore results available. next page_token: #{page[:next_page_token]}" if page[:next_page_token]
        ToolHelpers.text_response(body)
      end
    end
  end
end
