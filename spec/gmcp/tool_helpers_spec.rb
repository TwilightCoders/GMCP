require 'spec_helper'

RSpec.describe GMCP::ToolHelpers do
  describe '.define_tool capability gating' do
    let(:server) { instance_double('MCP::Server') }

    around do |example|
      original = ENV.fetch('GMCP_CAPABILITIES', :unset)
      example.run
    ensure
      original == :unset ? ENV.delete('GMCP_CAPABILITIES') : ENV['GMCP_CAPABILITIES'] = original
      GMCP::Capabilities.reset!
    end

    def with_capabilities(value)
      ENV['GMCP_CAPABILITIES'] = value
      GMCP::Capabilities.reset!
    end

    def define(capability)
      described_class.define_tool(
        server,
        name: 'a_tool',
        capability: capability,
        description: 'x',
        properties: {}
      ) { :called }
    end

    it 'registers a tool whose capability was granted' do
      with_capabilities('gmail.read')
      expect(server).to receive(:define_tool).once
      define('gmail.read')
    end

    it 'does not even define a tool whose capability was withheld' do
      with_capabilities('gmail.read')
      expect(server).not_to receive(:define_tool)
      expect(define('gmail.send')).to be_nil
    end

    it 'defines nothing at all under an empty grant set' do
      with_capabilities('')
      expect(server).not_to receive(:define_tool)
      expect(define('gmail.read')).to be_nil
    end

    it 'still registers tools that declare no capability' do
      with_capabilities('')
      expect(server).to receive(:define_tool).once
      define(nil)
    end

    it 'passes required through to the input schema when present' do
      with_capabilities('gmail.read')
      expect(server).to receive(:define_tool) do |name:, description:, input_schema:, &_blk|
        expect(name).to eq('a_tool')
        expect(description).to eq('x')
        expect(input_schema).to eq({ properties: { q: { type: 'string' } }, required: ['q'] })
      end
      described_class.define_tool(
        server,
        name: 'a_tool',
        capability: 'gmail.read',
        description: 'x',
        properties: { q: { type: 'string' } },
        required: ['q']
      ) { :called }
    end

    it 'omits required from the schema when not given' do
      with_capabilities('gmail.read')
      expect(server).to receive(:define_tool) do |input_schema:, **|
        expect(input_schema).to eq({ properties: {} })
      end
      define('gmail.read')
    end
  end
end
