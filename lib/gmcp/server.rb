require 'mcp'

module GMCP
  module Server
    SERVER_NAME    = 'gmcp'
    SERVER_VERSION = GMCP::VERSION

    def self.run!(accounts:)
      @registry = AccountRegistry.new(accounts: accounts)
      @registry.load_authorized_accounts!
      MCP::Server::Transports::StdioTransport.new(build_server).open
    end

    def self.reinitialize!(account:)
      registry.reinitialize!(account: account)
    end

    # Returns nil if account is ready, or an MCP error Response if not
    # authorized. Binds for the rest of the fiber; prefer with_account, which
    # scopes the binding to a block.
    def self.use_account(account)
      msg = registry.activate(account)
      msg && ToolHelpers.text_response(msg)
    end

    # Runs the block with `account` bound for the duration, restoring whatever
    # was bound before. The binding is fiber-local, so two concurrent tool calls
    # for different accounts cannot see each other's APIs.
    def self.with_account(account, &block)
      error, result = registry.scoped(account, &block)
      error ? ToolHelpers.text_response(error) : result
    end

    def self.build_server
      server = MCP::Server.new(name: SERVER_NAME, version: SERVER_VERSION)
      register_auth_tool(server)
      Gmail::Tools.register(server)
      Calendar::Tools.register(server)
      Drive::Tools.register(server)
      Voice::Tools.register(server)
      server
    end

    def self.register_auth_tool(server)
      ToolHelpers.define_tool(
        server,
        name: 'gmcp_authorize',
        capability: 'gmcp.authorize',
        description: 'Connect GMCP to a Google account. Opens a browser window for OAuth and captures the callback automatically.',
        properties: {
          account: {
            type: 'string',
            description: "Google account to authorize (configured: #{registry.account_description})"
          }
        }
      ) do |account: nil|
        account ||= registry.default_account

        unless ::File.exist?(Auth.credentials_path)
          next ToolHelpers.text_response(
            "credentials.json not found at #{Auth.credentials_path}.\n\n" \
            "1. Go to https://console.cloud.google.com/ → APIs & Services → Credentials\n" \
            "2. Create an OAuth 2.0 Client ID (Desktop app)\n" \
            "3. Download the JSON and save it to #{Auth.credentials_path}"
          )
        end

        begin
          url = Auth.authorize_interactive!(account: account, on_success: ->(acct) { Server.reinitialize!(account: acct) })
          ToolHelpers.text_response(
            "A browser window has opened for #{account}. Complete sign-in there — tools will become available automatically once you authorize.\n\n" \
            "If the browser did not open, use this URL manually:\n#{url}"
          )
        rescue => e
          ToolHelpers.text_response("Authorization failed: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        end
      end
    end

    def self.registry
      @registry ||= AccountRegistry.new(accounts: [])
    end

    private_class_method :build_server, :register_auth_tool, :registry
  end
end
