module GMCP
  module Apis
    GMAIL_BASE    = 'https://gmail.googleapis.com/gmail/v1/users/me/'
    CALENDAR_BASE = 'https://www.googleapis.com/calendar/v3/'
    DRIVE_BASE    = 'https://www.googleapis.com/drive/v3/'

    def self.build_for_account(account:)
      token = Auth.access_token(account:)
      {
        gmail:    build_api(GMAIL_BASE,    token),
        calendar: build_api(CALENDAR_BASE, token),
        drive:    build_api(DRIVE_BASE,    token)
      }
    end

    def self.build_api(base_url, token)
      Him::API.new(url: base_url) do |conn|
        conn.request :json
        conn.use BearerMiddleware, token: token
        conn.use Him::Middleware::DefaultParseJSON
        conn.adapter Faraday.default_adapter
      end
    end
    private_class_method :build_api
  end
end
