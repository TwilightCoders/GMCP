# frozen_string_literal: true

require 'spec_helper'

describe GMCP::Voice::Session do
  subject(:session) { described_class.new(cookies: { 'SAPISID' => 'fake-sapisid' }) }

  def respond_with(klass, code, body)
    resp = klass.new('1.1', code, 'msg')
    allow(resp).to receive(:body).and_return(body)
    allow(Net::HTTP).to receive(:start).and_return(resp)
  end

  it 'returns the parsed body on success' do
    respond_with(Net::HTTPOK, '200', '[["+15550100"]]')
    expect(session.call('account/get')).to eq([['+15550100']])
  end

  it 'raises AuthError on 401, so callers know to re-read cookies' do
    respond_with(Net::HTTPUnauthorized, '401', '{"error":{"message":"Request had invalid authentication credentials."}}')
    expect { session.call('account/get') }
      .to raise_error(described_class::AuthError, /HTTP 401 — Request had invalid authentication/)
  end

  it 'raises AuthError on 403' do
    respond_with(Net::HTTPForbidden, '403', 'Forbidden')
    expect { session.call('account/get') }.to raise_error(described_class::AuthError, /HTTP 403/)
  end

  it 'keeps other failures as OperationError' do
    respond_with(Net::HTTPBadRequest, '400', '{"error":{"message":"Invalid value"}}')
    expect { session.call('api2thread/list') }
      .to raise_error(described_class::OperationError, /HTTP 400 — Invalid value/)
  end
end

describe GMCP::Voice::Tools do
  after { described_class.reset_session! }

  it 'drops the memoized session on an auth failure so the next call re-reads cookies' do
    stale = instance_double(GMCP::Voice::Session)
    fresh = instance_double(GMCP::Voice::Session)
    allow(stale).to receive(:call).and_raise(GMCP::Voice::Session::AuthError, 'HTTP 401')
    allow(GMCP::Voice::Session).to receive(:new).and_return(stale, fresh)

    response = described_class.guarding { described_class.session.call('account/get') }

    expect(response.error?).to be(true)
    expect(response.content.first[:text]).to match(/Voice auth failed: HTTP 401/)
    expect(described_class.session).to be(fresh)
  end

  it 'keeps the session across ordinary API errors' do
    session = instance_double(GMCP::Voice::Session)
    allow(session).to receive(:call).and_raise(GMCP::Voice::Session::OperationError, 'HTTP 400')
    allow(GMCP::Voice::Session).to receive(:new).and_return(session)

    response = described_class.guarding { described_class.session.call('account/get') }

    expect(response.error?).to be(true)
    expect(described_class.session).to be(session)
    expect(GMCP::Voice::Session).to have_received(:new).once
  end
end
