# frozen_string_literal: true

module GMCP
  class AccountRegistry
    attr_reader :accounts

    def initialize(accounts:)
      @accounts = accounts
      @apis = {}
    end

    def load_authorized_accounts!
      accounts.each { |account| load_account(account) }
    end

    def reinitialize!(account:)
      @apis[account] = Apis.build_for_account(account:)
    end

    def default_account
      accounts.first
    end

    def account_description
      accounts.length == 1 ? default_account : accounts.join(', ')
    end

    def activate(account = nil)
      account ||= default_account
      apis = account && @apis[account]
      return authorization_message(account) unless apis

      bind_models!(apis)
      nil
    end

    private

    def load_account(account)
      @apis[account] = Apis.build_for_account(account:)
    rescue Auth::AuthRequired, Errno::ENOENT
      # Account hasn't been authorized yet — leave unbound, gmcp_authorize will fix it.
      nil
    rescue Signet::AuthorizationError, Google::Auth::AuthorizationError => e
      # Refresh token revoked or expired. Don't crash the whole server —
      # leave this account unbound and let the user re-authorize via gmcp_authorize.
      warn "GMCP: stored token for #{account} is no longer valid (#{e.message[0, 120]}); call gmcp_authorize to reconnect"
      nil
    end

    def bind_models!(apis)
      [Gmail::Message, Gmail::Thread, Gmail::Label, Gmail::Draft].each { |model| model.use_api(apis[:gmail]) }
      [Calendar::Event, Calendar::Calendar].each { |model| model.use_api(apis[:calendar]) }
      [Drive::File].each { |model| model.use_api(apis[:drive]) }
    end

    def authorization_message(account)
      if account && accounts.include?(account)
        "Not authorized for #{account}. Call gmcp_authorize(account: \"#{account}\")."
      elsif account
        "Unknown account #{account.inspect}. Configured: #{accounts.join(', ')}."
      else
        'Not authorized. Call gmcp_authorize.'
      end
    end
  end
end
