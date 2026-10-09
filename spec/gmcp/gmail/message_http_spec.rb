# frozen_string_literal: true

require 'spec_helper'

describe GMCP::Gmail::Message do
  let(:test_api) { Him::API.new(url: GMCP::Apis::GMAIL_BASE) }
  let(:empty_collection) { { parsed_data: { data: { messages: [] }, errors: {}, metadata: {} }, response: double('r') } }
  let(:empty_response)   { { parsed_data: { data: {}, errors: {}, metadata: {} }, response: double('r') } }

  around do |ex|
    original = described_class.instance_variable_get(:@_her_use_api)
    described_class.use_api(test_api)
    ex.run
  ensure
    described_class.instance_variable_set(:@_her_use_api, original)
  end

  before { allow(test_api).to receive(:request).and_return(empty_response) }

  describe '.search' do
    it 'GETs /messages with q and maxResults' do
      allow(test_api).to receive(:request).and_return(empty_collection)
      described_class.search('from:alice', max_results: 5)
      expect(test_api).to have_received(:request).with(
        hash_including(_method: :get, _path: 'messages', q: 'from:alice', maxResults: 5)
      )
    end
  end

  describe '.find' do
    it 'GETs /messages/:id' do
      allow(test_api).to receive(:request).and_return(
        { parsed_data: { data: { id: 'msg123' }, errors: {}, metadata: {} }, response: double('r', success?: true) }
      )
      described_class.find('msg123')
      expect(test_api).to have_received(:request).with(
        hash_including(_method: :get, _path: 'messages/msg123')
      )
    end
  end

  describe '#trash!' do
    it 'POSTs /messages/:id/trash' do
      described_class.new(id: 'msg123').trash!
      expect(test_api).to have_received(:request).with(
        hash_including(_method: :post, _path: 'messages/msg123/trash')
      )
    end
  end

  describe '#archive!' do
    it 'POSTs /messages/:id/modify with removeLabelIds: [INBOX]' do
      described_class.new(id: 'msg123').archive!
      expect(test_api).to have_received(:request).with(
        hash_including(_method: :post, _path: 'messages/msg123/modify', removeLabelIds: ['INBOX'])
      )
    end
  end

  describe '#modify!' do
    it 'POSTs /messages/:id/modify with supplied label changes' do
      described_class.new(id: 'msg123').modify!(addLabelIds: ['STARRED'], removeLabelIds: ['INBOX'])
      expect(test_api).to have_received(:request).with(
        hash_including(
          _method: :post,
          _path: 'messages/msg123/modify',
          addLabelIds: ['STARRED'],
          removeLabelIds: ['INBOX']
        )
      )
    end
  end

  describe '.send_message' do
    it 'POSTs /messages/send with base64url-encoded raw' do
      described_class.send_message(to: 'bob@example.com', subject: 'Hi', body: 'Hello')
      expect(test_api).to have_received(:request) do |params|
        expect(params[:_method]).to eq(:post)
        expect(params[:_path]).to eq('messages/send')
        raw = Base64.urlsafe_decode64(params[:raw])
        expect(raw).to include('To: bob@example.com')
        expect(raw).to include('Subject: Hi')
        expect(raw).to include('Hello')
      end
    end
  end

  describe '#reply!' do
    it 'POSTs /messages/send with correct threadId and Re: subject' do
      msg = described_class.new(
        id: 'msg123',
        threadId: 'thread456',
        payload: { 'headers' => [
          { 'name' => 'Subject', 'value' => 'Hello' },
          { 'name' => 'From',    'value' => 'alice@example.com' }
        ]}
      )
      msg.reply!(body: 'Thanks!')
      expect(test_api).to have_received(:request) do |params|
        expect(params[:_method]).to eq(:post)
        expect(params[:_path]).to eq('messages/send')
        expect(params[:threadId]).to eq('thread456')
        raw = Base64.urlsafe_decode64(params[:raw])
        expect(raw).to include('Subject: Re: Hello')
        expect(raw).to include('Thanks!')
      end
    end
  end
end
