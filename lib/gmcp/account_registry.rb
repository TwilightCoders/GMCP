# frozen_string_literal: true

module GMCP
  class AccountRegistry
    attr_reader :accounts

    def initialize(accounts:)
      @accounts = accounts
      @apis = {}
      ApiBinding.install!
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

    # The API set for an account, or nil if it is unknown or unauthorized.
    def apis_for(account = nil)
      account ||= default_account
      account && @apis[account]
    end

    # Runs the block with this account bound, restoring whatever was bound
    # before. Returns [error_message, nil] or [nil, block_result] so the caller
    # can tell an auth failure from a legitimately nil result.
    def scoped(account = nil)
      apis = apis_for(account)
      return [authorization_message(account || default_account), nil] unless apis

      [nil, ApiBinding.with(apis) { yield }]
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

    private

    def load_account(account)
      @apis[account] = Apis.build_for_account(account:)
    rescue Auth::AuthRequired, Errno::ENOENT
      nil # not authorized yet, or no credentials.json; gmcp_authorize reports which
    rescue Signet::AuthorizationError, Google::Auth::AuthorizationError => e
      # Refresh token revoked or expired. Don't crash the whole server —
      # leave this account unbound and let the user re-authorize via gmcp_authorize.
      warn "GMCP: stored token for #{account} is no longer valid (#{e.message[0, 120]}); call gmcp_authorize to reconnect"
      nil
    end
  end
end
