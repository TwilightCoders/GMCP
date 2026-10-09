require 'json'

module GMCP
  # A Google API request that came back 4xx/5xx. Without this, him hands an
  # error body back as if it were the resource, so a failed trash or send
  # reported success and a missing message surfaced as NoMethodError on nil.
  class ApiError < StandardError
    attr_reader :status

    def initialize(status, message)
      @status = status
      super("Google API error #{status}: #{message}")
    end

    # Sits next to the adapter so it sees the raw body before any JSON parsing.
    class Middleware < Faraday::Middleware
      def on_complete(env)
        return if env[:status] < 400

        raise ApiError.new(env[:status], message_from(env[:body]) || env[:reason_phrase] || 'request failed')
      end

      private

      def message_from(body)
        error = JSON.parse(body.to_s)['error']
        error.is_a?(Hash) ? error['message'] : error
      rescue JSON::ParserError
        body.to_s[0, 200] unless body.to_s.empty?
      end
    end
  end
end
