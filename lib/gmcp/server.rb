require 'mcp'

module GMCP
  module Server
    SERVER_NAME    = 'gmcp'
    SERVER_VERSION = GMCP::VERSION

    def self.run!(accounts:)
      @accounts = accounts
      @apis     = {}

      accounts.each do |account|
        begin
          @apis[account] = Apis.build_for_account(account:)
        rescue Auth::AuthRequired, Errno::ENOENT
          # Account needs authorization via gmcp_authorize
        end
      end

      MCP::Server::Transports::StdioTransport.new(build_server).open
    end

    def self.reinitialize!(account:)
      @apis[account] = Apis.build_for_account(account:)
    end

    # Returns nil if the account is ready (models bound), or a MCP error Response.
    def self.use_account(account)
      account ||= @accounts&.first
      apis = account && @apis[account]
      return bind_models!(apis) if apis

      msg = if account && @accounts&.include?(account)
        "Not authorized for #{account}. Call gmcp_authorize(account: \"#{account}\")."
      elsif account
        "Unknown account #{account.inspect}. Configured: #{@accounts&.join(', ')}."
      else
        "Not authorized. Call gmcp_authorize."
      end
      MCP::Tool::Response.new([{ type: 'text', text: msg }])
    end

    def self.bind_models!(apis)
      [Gmail::Message, Gmail::Thread, Gmail::Label, Gmail::Draft].each { |m| m.use_api(apis[:gmail]) }
      [Calendar::Event, Calendar::Calendar].each { |m| m.use_api(apis[:calendar]) }
      [Drive::File].each { |m| m.use_api(apis[:drive]) }
      nil
    end

    def self.build_server
      accounts = @accounts
      server = MCP::Server.new(name: SERVER_NAME, version: SERVER_VERSION)
      register_auth_tool(server, accounts: accounts)
      Gmail::Tools.register(server)
      Calendar::Tools.register(server)
      Drive::Tools.register(server)
      server
    end

    def self.register_auth_tool(server, accounts:)
      default_desc = accounts.length == 1 ? accounts.first : accounts.join(', ')
      server.define_tool(
        name: 'gmcp_authorize',
        description: 'Connect GMCP to a Google account. Opens a browser window for OAuth — authorize there and the token is captured automatically.',
        input_schema: {
          properties: {
            account: { type: 'string', description: "Google account to authorize (configured: #{default_desc})" }
          }
        }
      ) do |account: nil|
        account ||= accounts.first

        unless ::File.exist?(Auth::CREDENTIALS_PATH)
          next MCP::Tool::Response.new([{ type: 'text', text:
            "credentials.json not found at #{Auth::CREDENTIALS_PATH}.\n\n" \
            "1. Go to https://console.cloud.google.com/ → APIs & Services → Credentials\n" \
            "2. Create an OAuth 2.0 Client ID (Desktop app)\n" \
            "3. Download the JSON and save it to #{Auth::CREDENTIALS_PATH}"
          }])
        end

        begin
          Auth.authorize_interactive!(account: account, on_success: ->(acct) { Server.reinitialize!(account: acct) })
          MCP::Tool::Response.new([{ type: 'text', text: "A browser window has opened for #{account}. Complete sign-in there — tools will become available automatically once you authorize." }])
        rescue => e
          MCP::Tool::Response.new([{ type: 'text', text: "Authorization failed: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}" }])
        end
      end
    end

    private_class_method :build_server, :register_auth_tool
  end
end
