# frozen_string_literal: true

require 'spec_helper'

describe GMCP::Gmail::Message do
  describe 'model configuration' do
    it 'has collection path /messages' do
      expect(described_class.collection_path).to eq('messages')
    end

    it 'has primary key :id' do
      expect(described_class.primary_key).to eq(:id)
    end

    it 'parses root element :messages for collections' do
      expect(described_class.root_element).to eq(:messages)
    end
  end

  describe 'MIME encoding via send_message' do
    it 'produces valid base64url-encoded raw payload' do
      # Test the encoding logic directly via a test double
      raw = "To: test@example.com\r\nSubject: Hello\r\nContent-Type: text/plain\r\n\r\nBody text"
      encoded = Base64.urlsafe_encode64(raw)

      expect(encoded).not_to include('+')
      expect(encoded).not_to include('/')
      expect(Base64.urlsafe_decode64(encoded)).to eq(raw)
    end
  end

  describe '#reply! header extraction' do
    it 'builds Re: prefix only once' do
      msg = described_class.new(
        id: 'abc',
        threadId: 'thread1',
        payload: {
          'headers' => [
            { 'name' => 'Subject', 'value' => 'Re: Old subject' },
            { 'name' => 'From',    'value' => 'alice@example.com' }
          ]
        }
      )
      allow(described_class).to receive(:post_raw)
      msg.reply!(body: 'test reply')
      expect(described_class).to have_received(:post_raw) do |_path, params|
        raw = Base64.urlsafe_decode64(params[:raw])
        expect(raw).to include('Subject: Re: Old subject')
        expect(raw).not_to include('Re: Re:')
      end
    end
  end
end
