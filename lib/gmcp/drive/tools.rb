require 'mcp'

module GMCP
  module Drive
    module Tools
      ACCOUNT_PARAM = { account: { type: 'string', description: 'Google account to use (optional if only one is configured)' } }.freeze

      def self.register(server)
        server.define_tool(
          name: 'drive_search',
          description: 'Search Google Drive files using a query string',
          input_schema: {
            properties: {
              query:       { type: 'string', description: 'Drive query, e.g. "name contains \'report\' and mimeType=\'application/pdf\'"' },
              max_results: { type: 'integer' },
              **ACCOUNT_PARAM
            },
            required: ['query']
          }
        ) do |query:, max_results: 20, account: nil|
          auth_err = GMCP::Server.use_account(account)
          next auth_err if auth_err
          files = File.search(query, max_results: max_results)
          text = files.map { |f| "#{f.id}: #{f.name} (#{f.mimeType})" }.join("\n")
          MCP::Tool::Response.new([{ type: 'text', text: text.empty? ? 'No files found.' : text }])
        end

        server.define_tool(
          name: 'drive_list_folder',
          description: 'List files in a Drive folder',
          input_schema: {
            properties: {
              folder_id:   { type: 'string', description: 'Drive folder ID or "root"' },
              max_results: { type: 'integer' },
              **ACCOUNT_PARAM
            },
            required: ['folder_id']
          }
        ) do |folder_id:, max_results: 50, account: nil|
          auth_err = GMCP::Server.use_account(account)
          next auth_err if auth_err
          files = File.list_folder(folder_id, max_results: max_results)
          text = files.map { |f| "#{f.id}: #{f.name} (#{f.mimeType})" }.join("\n")
          MCP::Tool::Response.new([{ type: 'text', text: text.empty? ? 'Folder is empty.' : text }])
        end

        server.define_tool(
          name: 'drive_read_file',
          description: 'Download/read the content of a Drive file',
          input_schema: {
            properties: {
              file_id: { type: 'string' },
              **ACCOUNT_PARAM
            },
            required: ['file_id']
          }
        ) do |file_id:, account: nil|
          auth_err = GMCP::Server.use_account(account)
          next auth_err if auth_err
          content = File.download(file_id)
          MCP::Tool::Response.new([{ type: 'text', text: content.to_s }])
        end
      end
    end
  end
end
