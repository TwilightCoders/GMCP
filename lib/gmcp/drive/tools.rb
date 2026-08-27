require 'mcp'

module GMCP
  module Drive
    module Tools
      def self.register(server)
        ToolHelpers.define_tool(
          server,
          name: 'drive_search',
          capability: 'drive.read',
          description: 'Search Google Drive files using a query string',
          properties: {
            query:       { type: 'string', description: "Drive query, e.g. \"name contains 'report' and mimeType='application/pdf'\"" },
            max_results: { type: 'integer' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['query']
        ) do |query:, max_results: 20, account: nil|
          GMCP::Server.with_account(account) do
            files = File.search(query, max_results: max_results)
            ToolHelpers.list_response(files, empty_message: 'No files found.') { |f| "#{f.id}: #{f.name} (#{f.mimeType})" }
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'drive_list_folder',
          capability: 'drive.read',
          description: 'List files in a Drive folder',
          properties: {
            folder_id:   { type: 'string', description: 'Drive folder ID or "root"' },
            max_results: { type: 'integer' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['folder_id']
        ) do |folder_id:, max_results: 50, account: nil|
          GMCP::Server.with_account(account) do
            files = File.list_folder(folder_id, max_results: max_results)
            ToolHelpers.list_response(files, empty_message: 'Folder is empty.') { |f| "#{f.id}: #{f.name} (#{f.mimeType})" }
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'drive_read_file',
          capability: 'drive.read',
          description: 'Download/read the content of a Drive file',
          properties: {
            file_id: { type: 'string' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['file_id']
        ) do |file_id:, account: nil|
          GMCP::Server.with_account(account) do
            ToolHelpers.text_response(File.download(file_id).to_s)
          end
        end
      end
    end
  end
end
