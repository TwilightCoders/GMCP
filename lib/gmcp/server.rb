require 'mcp'

module GMCP
  module Server
    SERVER_NAME    = 'gmcp'
    SERVER_VERSION = GMCP::VERSION

    def self.run!(account:)
      Apis.setup!(account: account)

      bind_models!

      server = build_server
      transport = MCP::Server::Transports::StdioTransport.new(server)
      transport.open
    end

    def self.build_server
      server = MCP::Server.new(name: SERVER_NAME, version: SERVER_VERSION)
      Gmail::Tools.register(server)
      Calendar::Tools.register(server)
      Drive::Tools.register(server)
      server
    end

    def self.bind_models!
      [Gmail::Message, Gmail::Thread, Gmail::Label, Gmail::Draft].each { |m| m.use_api(Apis.gmail) }
      [Calendar::Event, Calendar::Calendar].each { |m| m.use_api(Apis.calendar) }
      [Drive::File].each { |m| m.use_api(Apis.drive) }
    end

    private_class_method :build_server, :bind_models!
  end
end
