# frozen_string_literal: true

require "yaml"

module GMCP
  # Capability gating for tool registration.
  #
  # GMCP fits a grant-based permission model in which a grant is
  # `(identity, connector_account, capabilities[])`. GMCP honors the two axes:
  #
  #   connector_account → GMCP_ACCOUNTS  (which mailboxes this process can reach)
  #   capabilities      → GMCP_CAPABILITIES (which verbs this process exposes)
  #
  # Gating happens at REGISTRATION, not invocation: a tool whose capability was
  # not granted is never defined on the MCP server, so it never appears in
  # tools/list and cannot be called no matter what the client sends. That is
  # deliberately stronger than a client-side --allowedTools flag, which depends
  # on the launcher assembling it correctly and the client honoring it.
  #
  # ── nil vs empty string is load-bearing ────────────────────────────────────
  #
  #   GMCP_CAPABILITIES unset (nil) → every capability. For a human running
  #                                   bin/gmcp directly with no grant system.
  #   GMCP_CAPABILITIES=""          → NO capabilities. The explicit empty grant
  #                                   set for an identity that was granted
  #                                   nothing.
  #
  # A launcher must therefore ALWAYS set the variable explicitly, including when
  # the grant set is empty. Omitting it conditionally ("no grants, so skip the
  # env var") fails open and hands the agent everything.
  module Capabilities
    # Loaded from config/capabilities.yml — that file is the source of truth,
    # and spec/gmcp/capability_manifest_spec.rb asserts it matches the tools
    # actually registered in lib/.
    MANIFEST_PATH = "config/capabilities.yml"

    def self.manifest
      @manifest ||= YAML.load_file(GMCP.root(MANIFEST_PATH)).freeze
    end

    # gmail / google_calendar / drive / voice are separate
    # connectors. One GMCP process serves all of them, and they do NOT share
    # account semantics — see ACCOUNT_SCOPING.
    def self.connectors
      @connectors ||= manifest.fetch("connectors").freeze
    end

    # Whether GMCP_ACCOUNTS constrains which principal a connector reaches.
    #
    #   enforced — it does; a grant's connector_account means what it says.
    #   ignored  — it does not; the principal is resolved outside GMCP, and a
    #              grant's connector_account is decorative for that connector.
    ACCOUNT_SCOPING = %w[enforced ignored].freeze

    # Where a connector's credential lives. Voice is `delegated`: Chrome holds
    # its session.
    CREDENTIAL_SOURCES = %w[local_file keychain delegated none].freeze

    def self.declared
      @declared ||= connectors.flat_map { |c| c.fetch("capabilities").map { |x| x.fetch("name") } }.freeze
    end

    # capability name => the connector hash that declares it
    def self.connector_index
      @connector_index ||= connectors.each_with_object({}) do |connector, index|
        connector.fetch("capabilities").each { |cap| index[cap.fetch("name")] = connector }
      end.freeze
    end

    def self.connector_for(capability)
      connector_index[capability]
    end

    def self.account_scoping_for(capability)
      connector_for(capability)&.fetch("account_scoping")
    end

    # Granted capabilities whose connector ignores GMCP_ACCOUNTS. These reach a
    # principal this process cannot narrow, so bin/gmcp says so on startup
    # rather than letting the account list imply a containment it does not have.
    def self.unscoped_grants
      granted.select { |cap| account_scoping_for(cap) == "ignored" }
    end

    ALL = declared

    ENV_VAR = 'GMCP_CAPABILITIES'

    class << self
      def granted
        @granted ||= parse(ENV.fetch(ENV_VAR, nil))
      end

      def enabled?(capability)
        return true if capability.nil?

        granted.include?(capability)
      end

      # Human-readable summary, used by bin/gmcp on startup so the operator can
      # see what this process is actually able to do.
      def summary
        if unrestricted?
          "all (#{ALL.length} capabilities; #{ENV_VAR} not set)"
        elsif granted.empty?
          "none (#{ENV_VAR} set but empty)"
        else
          granted.join(', ')
        end
      end

      def unrestricted?
        ENV.fetch(ENV_VAR, nil).nil?
      end

      # Test seam — capability state is read once and memoized.
      def reset!
        @granted = nil
      end

      private

      def parse(raw)
        return ALL.dup if raw.nil?

        requested = raw.split(',').map(&:strip).reject(&:empty?)
        unknown   = requested - ALL
        warn "GMCP: ignoring unknown #{ENV_VAR} entries: #{unknown.join(', ')}" if unknown.any?
        requested & ALL
      end
    end
  end
end
