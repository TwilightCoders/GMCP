# frozen_string_literal: true

require 'spec_helper'

describe GMCP::Gmail::Draft do
  describe 'MIME encoding via create_draft' do
    it 'encodes to/subject/body into a base64url raw message' do
      allow(described_class).to receive(:post_raw)

      described_class.create_draft(
        to: 'bob@example.com',
        subject: 'Test draft',
        body: 'Hello Bob!'
      )

      expect(described_class).to have_received(:post_raw) do |_path, params|
        raw = Base64.urlsafe_decode64(params[:message][:raw])
        expect(raw).to include('To: bob@example.com')
        expect(raw).to include('Subject: Test draft')
        expect(raw).to include('Hello Bob!')
      end
    end
  end
end
