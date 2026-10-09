# frozen_string_literal: true

module GMCP
  # Per-fiber binding of models to a set of account APIs.
  #
  # him resolves `use_api` at request time and calls it if it responds to
  # :call (him/lib/him/model/http.rb). Binding a *resolver* once therefore lets
  # the API in effect change per fiber without ever mutating class state again.
  #
  # This is what makes it safe for one process to serve more than one account:
  # writing the API onto the model class instead would let two concurrent
  # requests for different accounts race on process-global state.
  #
  # Binding is fiber-local (Thread.current[]) rather than thread-local, so it
  # holds under fiber schedulers as well as threads.
  module ApiBinding
    KEY = :gmcp_current_apis

    # Deferred so autoload is not forced at require time.
    MODELS = {
      gmail:    -> { [Gmail::Message, Gmail::Thread, Gmail::Label, Gmail::Draft] },
      calendar: -> { [Calendar::Event, Calendar::Calendar] },
      drive:    -> { [Drive::File] }
    }.freeze

    # Raised when a model issues a request with no account bound. Better than
    # him's NoMethodError on nil, and better than silently reusing whatever the
    # previous caller left behind.
    class NotBound < StandardError; end

    class << self
      # Idempotent — the resolvers only need installing once per process.
      def install!
        return if @installed

        MODELS.each do |service, models|
          resolver = -> { fetch(service) }
          models.call.each { |model| model.use_api(resolver) }
        end
        @installed = true
      end

      def current
        Thread.current[KEY]
      end

      def current=(apis)
        Thread.current[KEY] = apis
      end

      # Scopes a binding to a block and restores whatever was in effect before,
      # so a nested call cannot leak its account to its caller.
      def with(apis)
        previous = current
        self.current = apis
        yield
      ensure
        self.current = previous
      end

      def fetch(service)
        apis = current
        raise NotBound, "no account is bound on this fiber (wanted #{service})" if apis.nil?

        apis[service] || raise(NotBound, "bound account has no #{service} API")
      end

      # Test seam.
      def reset!
        @installed = false
        self.current = nil
      end
    end
  end
end
