module GMCP
  class BearerMiddleware < Faraday::Middleware
    def initialize(app, token:)
      super(app)
      @token = token
    end

    def call(env)
      env[:request_headers]['Authorization'] = "Bearer #{@token}"
      @app.call(env)
    end
  end
end
