# frozen_string_literal: true

require 'spec_helper'

describe GoogleStub do
  it 'drives a model through the real stack, with repeated params and auth' do
    google.get('/gmail/v1/users/me/labels') do |env|
      expect(env.request_headers['Authorization']).to eq('Bearer test-token')
      json(labels: [{ id: 'INBOX', name: 'INBOX' }])
    end

    expect(with_google { GMCP::Gmail::Label.all.map(&:id) }).to eq(['INBOX'])
    google.verify_stubbed_calls
  end
end
