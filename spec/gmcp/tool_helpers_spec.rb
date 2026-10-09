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

  describe '.json_response' do
    def body_of(response)
      response.content.first[:text]
    end

    # Him::Model does not include ActiveModel::Serializers::JSON, so a bare
    # to_json on one resolves to Object#to_json and yields the inspect string.
    # The tool then returns "#<GMCP::Gmail::Message:0x...>" and nothing else,
    # which is indistinguishable from success to a caller.
    it 'serializes a Him model by its attributes, not its object identity' do
      model = GMCP::Gmail::Message.new(id: 'abc123', snippet: 'hello', labelIds: %w[INBOX])

      parsed = JSON.parse(body_of(described_class.json_response(model)))

      expect(parsed).to include('id' => 'abc123', 'snippet' => 'hello', 'labelIds' => %w[INBOX])
    end

    it 'never emits an inspect string for a Him model' do
      model = GMCP::Gmail::Message.new(id: 'abc123')

      expect(body_of(described_class.json_response(model))).not_to include('#<')
    end

    it 'serializes a plain hash unchanged' do
      parsed = JSON.parse(body_of(described_class.json_response({ a: 1, b: %w[x y] })))

      expect(parsed).to eq({ 'a' => 1, 'b' => %w[x y] })
    end

    it 'serializes an array of Him models by their attributes' do
      models = [GMCP::Gmail::Message.new(id: 'one'), GMCP::Gmail::Message.new(id: 'two')]

      parsed = JSON.parse(body_of(described_class.json_response(models)))

      expect(parsed.map { |m| m['id'] }).to eq(%w[one two])
    end
  end
end

RSpec.describe GMCP::ToolHelpers, 'error handling' do
  let(:server) { MCP::Server.new(name: 'test') }

  def call(name, **args)
    server.tools.fetch(name).call(**args, server_context: nil)
  end

  def define(&block)
    described_class.define_tool(server, name: 't', description: 'x', properties: {}, &block)
  end

  it 'turns a Google API failure into an isError response with Google\'s message' do
    define { raise GMCP::ApiError.new(404, 'Requested entity was not found.') }

    response = call('t')
    expect(response.error?).to be(true)
    expect(response.content.first[:text]).to include('Requested entity was not found')
  end

  it 'turns an unexpected exception into an isError response naming it' do
    define { raise NoMethodError, 'boom' }

    expect { @response = call('t') }.to output(/GMCP tool error: NoMethodError/).to_stderr
    expect(@response.error?).to be(true)
    expect(@response.content.first[:text]).to eq('NoMethodError: boom')
  end

  it 'leaves a successful response alone' do
    define { described_class.text_response('ok') }

    expect(call('t').error?).to be(false)
  end

  describe '.account_tool' do
    it 'adds the account parameter and binds that account around the block' do
      allow(GMCP::Server).to receive(:with_account) { |_account, &blk| blk.call }
      described_class.account_tool(server, name: 'a', description: 'x', properties: { q: { type: 'string' } }) do |q:|
        described_class.text_response(q)
      end

      expect(server.tools.fetch('a').input_schema.to_h[:properties].keys).to contain_exactly(:q, :account)
      expect(call('a', q: 'hi', account: 'me@example.com').content.first[:text]).to eq('hi')
      expect(GMCP::Server).to have_received(:with_account).with('me@example.com')
    end
  end
end
