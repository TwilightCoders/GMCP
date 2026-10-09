# frozen_string_literal: true

require 'spec_helper'

describe GMCP::Gmail::Draft do
  describe '.create_draft' do
    it 'POSTs the message built by Mime' do
      google.post('/gmail/v1/users/me/drafts') do |env|
        raw = Base64.urlsafe_decode64(JSON.parse(env.body).dig('message', 'raw'))
        head, body = raw.split("\r\n\r\n", 2)
        expect(head).to include('To: bob@example.com', 'Subject: Test draft', 'MIME-Version: 1.0')
        expect(Base64.decode64(body)).to eq('Hello Bob!')
        json(id: 'd1')
      end

      with_google { described_class.create_draft(to: 'bob@example.com', subject: 'Test draft', body: 'Hello Bob!') }
      google.verify_stubbed_calls
    end

    it 'refuses header injection before anything is sent' do
      expect do
        with_google { described_class.create_draft(to: "bob@example.com\r\nBcc: eve@x", subject: 's', body: 'b') }
      end.to raise_error(ArgumentError)
    end
  end
end
