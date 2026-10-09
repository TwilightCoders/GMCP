# frozen_string_literal: true

require 'spec_helper'

describe GMCP::ApiError::Middleware do
  def connection(status, body)
    Faraday.new do |conn|
      conn.use described_class
      conn.adapter(:test) { |stub| stub.get('/x') { [status, { 'Content-Type' => 'application/json' }, body] } }
    end
  end

  it 'raises with Google\'s own error message on a 4xx' do
    body = '{"error":{"code":404,"message":"Requested entity was not found."}}'

    expect { connection(404, body).get('/x') }
      .to raise_error(GMCP::ApiError, /404: Requested entity was not found/) { |e| expect(e.status).to eq(404) }
  end

  it 'falls back to the raw body when the error is not JSON' do
    expect { connection(502, 'Bad Gateway').get('/x') }.to raise_error(GMCP::ApiError, /502: Bad Gateway/)
  end

  it 'passes a success through untouched' do
    expect(connection(200, '{"id":"1"}').get('/x').body).to eq('{"id":"1"}')
  end
end
