# frozen_string_literal: true

require 'mcp'

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

    def self.json_response(object)
      text_response(object.to_json)
    end

    # Registers a tool, unless `capability:` names a capability this process was
    # not granted — in which case the tool is never defined and therefore never
    # appears in tools/list. See GMCP::Capabilities.
    #
    # Returns the tool on registration, nil when gated out.
    def self.define_tool(server, name:, description:, properties:, required: nil, capability: nil, &block)
      declarations[name] = capability
      return nil unless Capabilities.enabled?(capability)

      schema = { properties: properties }
      schema[:required] = required if required
      server.define_tool(name: name, description: description, input_schema: schema, &block)
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
