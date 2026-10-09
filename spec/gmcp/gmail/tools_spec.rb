# frozen_string_literal: true

require 'spec_helper'

# Drives registered tools end to end through ToolHelpers.guarded, which is
# where errors are meant to become isError responses.
describe GMCP::Gmail::Tools, 'registered tools' do
  let(:handlers) { {} }

  around do |example|
    original = ENV.fetch('GMCP_CAPABILITIES', :unset)
    ENV.delete('GMCP_CAPABILITIES')
    GMCP::Capabilities.reset!
    example.run
  ensure
    original == :unset ? ENV.delete('GMCP_CAPABILITIES') : ENV['GMCP_CAPABILITIES'] = original
    GMCP::Capabilities.reset!
  end

  before do
    server = double('MCP::Server')
    allow(server).to receive(:define_tool) { |name:, **, &handler| handlers[name] = handler }
    allow(GMCP::Server).to receive(:with_account) { |_account, &block| block.call }
    described_class.register(server)
  end

  def call(name, **args)
    handlers.fetch(name).call(**args)
  end

  describe 'gmail_unsubscribe' do
    it 'explains an unsupported sender as an error, in the user’s terms' do
      allow(GMCP::Gmail::Unsubscribe).to receive(:one_click!)
        .and_raise(GMCP::Gmail::Unsubscribe::NotSupported, 'mailto only')
      r = call('gmail_unsubscribe', message_id: 'm1')
      expect(r.error?).to be(true)
      expect(r.content.first[:text]).to eq('Cannot one-click unsubscribe: mailto only')
    end

    it 'reports a refused unsubscribe as an error' do
      allow(GMCP::Gmail::Unsubscribe).to receive(:one_click!)
        .and_raise(GMCP::Gmail::Unsubscribe::Failed, 'unsubscribe endpoint returned HTTP 500')
      r = call('gmail_unsubscribe', message_id: 'm1')
      expect(r.error?).to be(true)
      expect(r.content.first[:text]).to include('HTTP 500')
    end

    it 'leaves any other failure to the shared handler' do
      allow(GMCP::Gmail::Unsubscribe).to receive(:one_click!).and_raise(GMCP::ApiError.new(404, 'Not Found'))
      r = call('gmail_unsubscribe', message_id: 'm1')
      expect(r.error?).to be(true)
      expect(r.content.first[:text]).to eq('Google API error 404: Not Found')
    end
  end

  describe 'gmail_batch_trash' do
    it "reports Gmail's limit as an error" do
      ids = Array.new(GMCP::Gmail::Message::BATCH_LIMIT + 1) { |i| "id#{i}" }
      r = call('gmail_batch_trash', message_ids: ids)
      expect(r.error?).to be(true)
      expect(r.content.first[:text]).to match(/exceeds Gmail's limit/)
    end

    it 'reports an API failure as an error' do
      google.post('/gmail/v1/users/me/messages/batchModify') { json({ error: { message: 'Forbidden' } }, status: 403) }
      r = with_google { call('gmail_batch_trash', message_ids: %w[a]) }
      expect(r.error?).to be(true)
      expect(r.content.first[:text]).to include('403')
    end
  end
end
