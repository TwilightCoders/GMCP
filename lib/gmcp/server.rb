require 'mcp'

# mcp validates schemas with json-schema, which warns on every start unless
# told to use the stdlib JSON it already has.
require 'json-schema'
JSON::Validator.use_multi_json = false

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

    # Runs the block with `account` bound for the duration, restoring whatever
    # was bound before. The binding is fiber-local, so two concurrent tool calls
    # for different accounts cannot see each other's APIs.
    def self.with_account(account, &block)
      error, result = registry.scoped(account, &block)
      error ? ToolHelpers.error_response(error) : result
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

        next ToolHelpers.error_response(registry.authorization_message(account)) unless registry.accounts.include?(account)

        unless ::File.exist?(Auth.credentials_path)
          next ToolHelpers.error_response(
            "credentials.json not found at #{Auth.credentials_path}.\n\n" \
            "1. Go to https://console.cloud.google.com/ → APIs & Services → Credentials\n" \
            "2. Create an OAuth 2.0 Client ID (Desktop app)\n" \
            "3. Download the JSON and save it to #{Auth.credentials_path}"
          )
        end

        url = Auth.authorize_interactive!(account: account, on_success: ->(acct) { Server.reinitialize!(account: acct) })
        ToolHelpers.text_response(
          "A browser window has opened for #{account}. Complete sign-in there — tools will become available automatically once you authorize.\n\n" \
          "If the browser did not open, use this URL manually:\n#{url}"
        )
      end
    end

    def self.registry
      @registry ||= AccountRegistry.new(accounts: [])
    end

    private_class_method :build_server, :register_auth_tool, :registry
  end
end
