require 'googleauth'
require 'googleauth/stores/file_token_store'

module GMCP
  module Auth
    CREDENTIALS_PATH = File.expand_path('~/.config/gmcp/credentials.json').freeze

    class AuthRequired < StandardError; end

    def self.token_path(account)
      File.expand_path("~/.config/gmcp/#{account}/token.yaml")
    end

    def self.scopes
      require 'yaml'
      @scopes ||= YAML.load_file(GMCP.root('config', 'scopes.yml')).values.flatten
    end

    # Returns refreshed UserRefreshCredentials for the given account.
    # Raises AuthRequired if the account has no stored token.
    def self.credentials(account:)
      FileUtils.mkdir_p(File.dirname(token_path(account)))
      store = Google::Auth::Stores::FileTokenStore.new(file: token_path(account))
      client_id = Google::Auth::ClientId.from_file(CREDENTIALS_PATH)
      authorizer = Google::Auth::UserAuthorizer.new(client_id, scopes, store)
      creds = authorizer.get_credentials(account)
      if creds.nil?
        url = authorizer.get_authorization_url(base_url: 'urn:ietf:wg:oauth:2.0:oob')
        raise AuthRequired, "Account #{account.inspect} has no stored token.\n" \
          "Authorize via: #{url}\n" \
          "Then run: gmcp auth #{account} <code>"
      end
      creds.refresh! if creds.expired?
      creds
    end

    def self.access_token(account:)
      credentials(account:).access_token
    end
  end
end
