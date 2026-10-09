require 'googleauth'
require 'googleauth/token_store'
require 'securerandom'
require 'webrick'
require 'yaml'

module GMCP
  module Auth
    CONFIG_DIR = File.expand_path('~/.config/gmcp').freeze
    DEFAULT_CREDENTIALS_PATH = File.join(CONFIG_DIR, 'credentials.json').freeze
    CALLBACK_PATH  = '/oauth2callback'
    AUTH_TIMEOUT   = 900
    REFRESH_MARGIN = 60
    # An email address, and nothing that could climb out of CONFIG_DIR.
    ACCOUNT_FORMAT = /\A[^\s\/\\@]+@[^\s\/\\@]+\z/
    AUTH_SUCCESS_HTML = '<html><body><h2>Authorized! You can close this tab.</h2></body></html>'
    AUTH_FAILURE_HTML = '<html><body><h2>Authorization failed — no code returned.</h2></body></html>'

    class AuthRequired < StandardError; end

    # Refresh tokens are long-lived secrets: written owner-only, atomically, and
    # never created as a side effect of a read. googleauth's FileTokenStore
    # wraps YAML::Store, whose read transaction creates an empty file under the
    # process umask, which left 0644 token.yaml files for accounts that were
    # never authorized. The on-disk format is the same, so existing tokens load.
    class TokenStore < Google::Auth::TokenStore
      def initialize(path)
        super()
        @path = path
      end

      def load(id)
        read[id]
      end

      def store(id, token)
        write(read.merge(id => token))
      end

      def delete(id)
        write(read.except(id))
      end

      private

      def read
        return {} unless File.size?(@path)

        File.chmod(0o600, @path) unless (File.stat(@path).mode & 0o077).zero? # tighten older files
        YAML.safe_load_file(@path) || {}
      end

      def write(data)
        FileUtils.mkdir_p(File.dirname(@path), mode: 0o700)
        tmp = "#{@path}.#{Process.pid}.tmp"
        File.write(tmp, YAML.dump(data), perm: 0o600)
        File.rename(tmp, @path)
      end
    end

    class << self
      def credentials_path
        ENV.fetch('GMCP_CREDENTIALS_FILE', DEFAULT_CREDENTIALS_PATH)
      end

      def token_path(account)
        raise ArgumentError, "not an email address: #{account.inspect}" unless account.to_s.match?(ACCOUNT_FORMAT)

        File.join(CONFIG_DIR, account, 'token.yaml')
      end

      def scopes
        @scopes ||= YAML.load_file(GMCP.root('config', 'scopes.yml')).values.flatten.freeze
      end

      # Live credentials for an account, refreshed when within REFRESH_MARGIN
      # of expiry. Held per account so a refresh is shared by every request,
      # and serialized so concurrent requests do not all refresh at once.
      def credentials(account:)
        lock.synchronize do
          creds = (cache[account] ||= load_credentials(account))
          creds.refresh! if creds.expires_within?(REFRESH_MARGIN)
          creds
        end
      end

      def access_token(account:)
        credentials(account:).access_token
      end

      # Opens Google's consent page in a browser and returns its URL. The code
      # exchange completes on a background thread when Google redirects to the
      # loopback callback; exactly one of on_success / on_failure is called,
      # unless the timeout passes first.
      def authorize_interactive!(account:, on_success:, on_failure: nil, timeout: AUTH_TIMEOUT)
        token_path(account) # validates before anything touches disk or network
        state  = SecureRandom.urlsafe_base64(24)
        server = WEBrick::HTTPServer.new(
          BindAddress: '127.0.0.1', Port: 0,
          Logger: WEBrick::Log.new(File::NULL), AccessLog: []
        )
        base_url = "http://127.0.0.1:#{server.config[:Port]}"
        on_failure ||= ->(_acct, error) { warn "GMCP auth error: #{error.class}: #{error.message}" }

        server.mount_proc(CALLBACK_PATH) do |req, res|
          handle_callback(req, res, server:, state:, account:, base_url:, on_success:, on_failure:)
        end
        serve(server, timeout)

        url = authorizer.get_authorization_url(base_url:, state:, login_hint: account)
        open_browser(url)
        url
      end

      # Test seam.
      def reset!
        @cache = @authorizer = @client_id = nil
      end

      private

      def lock
        @lock ||= Mutex.new
      end

      def cache
        @cache ||= {}
      end

      def load_credentials(account)
        raise AuthRequired, "No stored token for #{account.inspect}" unless File.size?(token_path(account))

        authorizer(account).get_credentials(account) ||
          raise(AuthRequired, "Stored token for #{account.inspect} lacks the required scopes")
      end

      def client_id
        @client_id ||= Google::Auth::ClientId.from_file(credentials_path)
      end

      # One authorizer per token file; with no account, one for building the
      # consent URL, which never reads or writes a token.
      def authorizer(account = nil)
        store = account ? TokenStore.new(token_path(account)) : TokenStore.new(File::NULL)
        Google::Auth::UserAuthorizer.new(client_id, scopes, store)
      end

      # Requests that do not carry our state are ignored rather than ending the
      # flow, so a stray or forged hit cannot cancel or hijack a sign-in.
      def handle_callback(req, res, server:, state:, account:, base_url:, on_success:, on_failure:)
        res['Content-Type'] = 'text/html'
        unless req.query['state'] == state
          res.status = 400
          res.body = AUTH_FAILURE_HTML
          return
        end

        code = req.query['code']
        res.body = code ? AUTH_SUCCESS_HTML : AUTH_FAILURE_HTML
        server.shutdown
        return on_failure.call(account, AuthRequired.new(req.query['error'] || 'no code returned')) unless code

        Thread.new do
          authorizer(account).get_and_store_credentials_from_code(user_id: account, code:, base_url:)
          lock.synchronize { cache.delete(account) }
          on_success.call(account)
        rescue StandardError => e
          on_failure.call(account, e)
        end
      end

      def serve(server, timeout)
        Thread.new { server.start }
        Thread.new do
          sleep timeout
          server.shutdown
        end
      end

      def open_browser(url)
        case RbConfig::CONFIG['host_os']
        when /darwin/      then system('open', url)
        when /linux/       then system('xdg-open', url)
        when /mswin|mingw/ then system('start', url)
        end
      end
    end
  end
end
