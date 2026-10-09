# frozen_string_literal: true

require 'spec_helper'
require 'faraday'

describe GMCP::BearerMiddleware do
  let(:token) { 'test-access-token-abc123' }

  def build_app(token)
    captured = {}
    middleware = described_class.new(
      ->(env) { captured[:auth] = env[:request_headers]['Authorization']; [200, {}, ''] },
      token: token
    )
    [middleware, captured]
  end

  it 'adds Authorization: Bearer header to every request' do
    app, captured = build_app(token)
    env = Faraday::Env.new
    env[:request_headers] = Faraday::Utils::Headers.new
    app.call(env)
    expect(captured[:auth]).to eq("Bearer #{token}")
  end

  it 'does not clobber other request headers' do
    app, captured = build_app(token)
    env = Faraday::Env.new
    env[:request_headers] = Faraday::Utils::Headers.new({ 'Content-Type' => 'application/json' })
    app.call(env)
    expect(captured[:auth]).to eq("Bearer #{token}")
    expect(env[:request_headers]['Content-Type']).to eq('application/json')
  end
end

describe GMCP::BearerMiddleware, 'with a token provider' do
  it 'asks the provider on every request, so a refreshed token is picked up' do
    tokens = %w[first second].each
    seen = []
    middleware = described_class.new(->(env) { seen << env[:request_headers]['Authorization'] }, token: -> { tokens.next })

    2.times do
      env = Faraday::Env.new
      env[:request_headers] = Faraday::Utils::Headers.new
      middleware.call(env)
    end

    expect(seen).to eq(['Bearer first', 'Bearer second'])
  end
end
