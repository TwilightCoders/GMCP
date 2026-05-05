require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'socket'
require 'uri'
require 'webrick'
require 'timeout'

module GMCP
  module Auth
    DEFAULT_CREDENTIALS_PATH = File.expand_path('~/.config/gmcp/credentials.json').freeze
    CALLBACK_PATH = '/oauth2callback'
    AUTH_TIMEOUT  = 300
    AUTH_SUCCESS_HTML = '<html><body><h2>Authorized! You can close this tab.</h2></body></html>'
    AUTH_FAILURE_HTML = '<html><body><h2>Authorization failed — no code returned.</h2></body></html>'

    class AuthRequired < StandardError; end

    def self.credentials_path
      ENV.fetch('GMCP_CREDENTIALS_FILE', DEFAULT_CREDENTIALS_PATH)
    end

    def self.token_path(account)
      File.expand_path("~/.config/gmcp/#{account}/token.yaml")
    end

    def self.scopes
      require 'yaml'
      @scopes ||= YAML.load_file(GMCP.root('config', 'scopes.yml')).values.flatten
    end

    def self.credentials(account:)
      creds = authorizer_for(account).get_credentials(account)
      raise AuthRequired, "No stored token for #{account.inspect}" if creds.nil?

      creds.refresh! if creds.expired?
      creds
    end

    def self.access_token(account:)
      credentials(account:).access_token
    end

    # Opens a browser to Google's OAuth consent page and returns the authorization URL.
    # Auth completes in a background thread when Google redirects to the callback.
    # Calls on_success.call(account) when the token is stored.
    def self.authorize_interactive!(account:, on_success:)
      port     = free_port
      base_url = "http://localhost:#{port}"
      url      = with_login_hint(
        authorizer_for(account).get_authorization_url(base_url: base_url),
        account
      )

      server = build_callback_server(account: account, base_url: base_url, port: port, on_success: on_success)
      start_callback_server(server)

      open_browser(url)
      url
    end

    # Append login_hint=<account> so Google's consent screen pre-selects the
    # right account when the user has multiple Google accounts signed in.
    # The googleauth gem's get_authorization_url doesn't expose this directly
    # across all versions, so append it as a URL parameter manually.
    def self.with_login_hint(url, account)
      return url if account.nil? || account.empty?
      separator = url.include?('?') ? '&' : '?'
      "#{url}#{separator}login_hint=#{URI.encode_www_form_component(account)}"
    end
    private_class_method :with_login_hint

    def self.authorizer_for(account)
      FileUtils.mkdir_p(File.dirname(token_path(account)))
      store     = Google::Auth::Stores::FileTokenStore.new(file: token_path(account))
      client_id = Google::Auth::ClientId.from_file(credentials_path)
      Google::Auth::UserAuthorizer.new(client_id, scopes, store)
    end
    private_class_method :authorizer_for

    def self.build_callback_server(account:, base_url:, port:, on_success:)
      null_log = WEBrick::Log.new(File.open(File::NULL, 'w'))
      server = WEBrick::HTTPServer.new(Port: port, Logger: null_log, AccessLog: [])
      context = callback_context(server: server, account: account, base_url: base_url, on_success: on_success)
      server.mount_proc(CALLBACK_PATH) do |req, res|
        handle_callback(req: req, res: res, context: context)
      end
      server
    end
    private_class_method :build_callback_server

    def self.handle_callback(req:, res:, context:)
      code = req.query['code']
      res['Content-Type'] = 'text/html'
      if code
        res.body = AUTH_SUCCESS_HTML
        exchange_code_async(
          account: context[:account],
          code: code,
          base_url: context[:base_url],
          on_success: context[:on_success]
        )
      else
        res.body = AUTH_FAILURE_HTML
      end
      context[:server].shutdown
    end
    private_class_method :handle_callback

    def self.callback_context(server:, account:, base_url:, on_success:)
      { server: server, account: account, base_url: base_url, on_success: on_success }
    end
    private_class_method :callback_context

    def self.exchange_code_async(account:, code:, base_url:, on_success:)
      Thread.new do
        authorizer_for(account).get_and_store_credentials_from_code(
          user_id: account, code: code, base_url: base_url
        )
        on_success.call(account)
      rescue StandardError => e
        warn "GMCP auth error: #{e.class}: #{e.message}"
      end
    end
    private_class_method :exchange_code_async

    def self.start_callback_server(server)
      Thread.new do
        Timeout.timeout(AUTH_TIMEOUT) { server.start }
      rescue Timeout::Error
        server.shutdown
      end
    end
    private_class_method :start_callback_server

    def self.free_port
      s = TCPServer.new('localhost', 0)
      s.addr[1]
    ensure
      s&.close
    end
    private_class_method :free_port

    def self.open_browser(url)
      case RbConfig::CONFIG['host_os']
      when /darwin/      then system('open', url)
      when /linux/       then system('xdg-open', url)
      when /mswin|mingw/ then system('start', url)
      end
    end
    private_class_method :open_browser
  end
end
