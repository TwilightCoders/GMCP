module GMCP
  # Sets the Authorization header from a token provider called per request, so
  # a long-running server picks up refreshed access tokens instead of sending
  # the one it started with until Google rejects it an hour later.
  class BearerMiddleware < Faraday::Middleware
    def initialize(app, token:)
      super(app)
      @token = token
    end

    def call(env)
      token = @token.respond_to?(:call) ? @token.call : @token
      env[:request_headers]['Authorization'] = "Bearer #{token}"
      @app.call(env)
    end
  end
end
