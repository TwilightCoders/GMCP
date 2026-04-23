require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'webrick'
require 'securerandom'
require 'timeout'

module GMCP
  module Auth
    CREDENTIALS_PATH = File.expand_path('~/.config/gmcp/credentials.json').freeze
    CALLBACK_PATH = '/oauth2callback'
    AUTH_TIMEOUT  = 300

    class AuthRequired < StandardError; end

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

    # Opens a browser to Google's OAuth consent page and returns immediately.
    # Auth completes in a background thread when Google redirects to the callback.
    # Calls on_success.call(account) when the token is stored.
    def self.authorize_interactive!(account:, on_success:)
      port     = free_port
      base_url = "http://localhost:#{port}"
      url      = authorizer_for(account).get_authorization_url(base_url: base_url)

      null_log = WEBrick::Log.new(File.open(File::NULL, 'w'))
      server = WEBrick::HTTPServer.new(Port: port, Logger: null_log, AccessLog: [])
      server.mount_proc(CALLBACK_PATH) do |req, res|
        code = req.query['code']
        res['Content-Type'] = 'text/html'
        if code
          res.body = '<html><body><h2>Authorized! You can close this tab.</h2></body></html>'
          Thread.new do
            authorizer_for(account).get_and_store_credentials_from_code(
              user_id: account, code: code, base_url: base_url
            )
            on_success.call(account)
          rescue => e
            $stderr.puts "GMCP auth error: #{e.class}: #{e.message}"
          end
        else
          res.body = '<html><body><h2>Authorization failed — no code returned.</h2></body></html>'
        end
        server.shutdown
      end

      Thread.new do
        Timeout.timeout(AUTH_TIMEOUT) { server.start }
      rescue Timeout::Error
        server.shutdown
      end

      open_browser(url)
    end

    def self.authorizer_for(account)
      FileUtils.mkdir_p(File.dirname(token_path(account)))
      store     = Google::Auth::Stores::FileTokenStore.new(file: token_path(account))
      client_id = Google::Auth::ClientId.from_file(CREDENTIALS_PATH)
      Google::Auth::UserAuthorizer.new(client_id, scopes, store)
    end
    private_class_method :authorizer_for

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
