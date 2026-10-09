# frozen_string_literal: true

require 'mcp'
require 'json'

module GMCP
  module ToolHelpers
    ACCOUNT_PARAM = {
      account: {
        type: 'string',
        description: 'Google account to use (optional if only one is configured)'
      }
    }.freeze

    def self.text_response(text)
      MCP::Tool::Response.new([{ type: 'text', text: text }])
    end

    # Marked isError, so the client knows the call failed rather than having to
    # guess from the wording.
    def self.error_response(text)
      MCP::Tool::Response.new([{ type: 'text', text: text }], error: true)
    end

    # Him models do not include ActiveModel::Serializers::JSON, so `to_json` on
    # one resolves to Object#to_json and yields the inspect string —
    # "#<GMCP::Gmail::Message:0x...>". That is valid JSON and completely empty
    # of the record, so a caller cannot tell it from success. Serialize by
    # attributes instead, recursing so a collection of models does not hit the
    # same wall one level down.
    def self.json_response(object)
      text_response(JSON.pretty_generate(serializable(object)))
    end

    def self.serializable(object)
      case object
      when Array then object.map { |item| serializable(item) }
      when Hash  then object.to_h { |key, value| [key, serializable(value)] }
      else
        object.respond_to?(:attributes) ? serializable(object.attributes) : object
      end
    end

    # Registers a tool, unless `capability:` names a capability this process was
    # not granted — in which case the tool is never defined and therefore never
    # appears in tools/list. See GMCP::Capabilities.
    #
    # Returns the tool on registration, nil when gated out.
    #
    # Every failure becomes an isError response here, once, instead of each
    # tool rescuing its own way or letting the exception escape as a JSON-RPC
    # internal error that hides the cause.
    def self.define_tool(server, name:, description:, properties:, required: nil, capability: nil, &block)
      declarations[name] = capability
      return nil unless Capabilities.enabled?(capability)

      schema = { properties: properties }
      schema[:required] = required if required
      # Declared with **args, so MCP passes server_context; the tool blocks do
      # not take it. MCP installs this as the tool's own `call`, so self is the
      # tool there: name the module explicitly.
      handler = lambda do |**args|
        args.delete(:server_context)
        ToolHelpers.guarded { block.call(**args) }
      end
      server.define_tool(name: name, description: description, input_schema: schema, &handler)
    end

    # A tool that acts on a Google account: adds the `account` parameter and
    # runs the block with that account bound.
    def self.account_tool(server, properties:, **options, &block)
      define_tool(server, properties: properties.merge(ACCOUNT_PARAM), **options) do |account: nil, **args|
        GMCP::Server.with_account(account) { block.call(**args) }
      end
    end

    def self.guarded
      yield
    rescue ApiError, Auth::AuthRequired, ApiBinding::NotBound, ArgumentError => e
      error_response(e.message)
    rescue Signet::AuthorizationError => e
      error_response("Google rejected the stored token (#{e.message.lines.first&.strip}). Call gmcp_authorize to reconnect.")
    rescue StandardError => e
      warn "GMCP tool error: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
      error_response("#{e.class}: #{e.message}")
    end

    def self.list_response(items, empty_message:, &formatter)
      lines = items.map(&formatter).join("\n")
      text_response(lines.empty? ? empty_message : lines)
    end

    # Every (tool name => capability) pair this process has attempted to
    # register, granted or not. Populated as a side effect of define_tool, so it
    # cannot drift from what the tools actually declare — which is what makes
    # the manifest consistency spec exact rather than a regex over source.
    def self.declarations
      @declarations ||= {}
    end

    def self.reset_declarations!
      @declarations = {}
    end
  end
end
