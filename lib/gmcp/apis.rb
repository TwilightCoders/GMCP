module GMCP
  module Apis
    GMAIL_BASE    = 'https://gmail.googleapis.com/gmail/v1/users/me/'
    CALENDAR_BASE = 'https://www.googleapis.com/calendar/v3/'
    DRIVE_BASE    = 'https://www.googleapis.com/drive/v3/'

    # Fails fast (AuthRequired, or a refresh error) when the account has no
    # usable token, then resolves the access token per request so it is
    # refreshed as it nears expiry.
    def self.build_for_account(account:)
      Auth.credentials(account:)
      build(token: -> { Auth.access_token(account:) })
    end

    # The adapter is a seam for specs, which run the real middleware stack
    # against Faraday's :test adapter.
    def self.build(token:, adapter: [Faraday.default_adapter])
      {
        gmail:    build_api(GMAIL_BASE,    token, adapter),
        calendar: build_api(CALENDAR_BASE, token, adapter),
        drive:    build_api(DRIVE_BASE,    token, adapter)
      }
    end

    def self.build_api(base_url, token, adapter)
      Him::API.new(url: base_url) do |conn|
        conn.options.params_encoder = Faraday::FlatParamsEncoder # labelIds=a&labelIds=b, as Google expects
        conn.request :json
        conn.use BearerMiddleware, token: token
        conn.use Him::Middleware::DefaultParseJSON
        conn.use ApiError::Middleware
        conn.adapter(*adapter)
      end
    end
    private_class_method :build_api
  end
end
