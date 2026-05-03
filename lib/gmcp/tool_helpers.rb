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

    def self.define_tool(server, name:, description:, properties:, required: nil, &block)
      schema = { properties: properties }
      schema[:required] = required if required
      server.define_tool(name: name, description: description, input_schema: schema, &block)
    end

    def self.list_response(items, empty_message:, &formatter)
      lines = items.map(&formatter).join("\n")
      text_response(lines.empty? ? empty_message : lines)
    end
  end
end
