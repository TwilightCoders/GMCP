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

describe GMCP::Voice::Session, '.for' do
  it 'reports a missing or failed profile read as an AuthError' do
    allow(GMCP::Voice::Chrome).to receive(:cookies).and_raise(GMCP::Voice::Chrome::Error, 'No Voice sign-in')

    expect { described_class.for('me@example.com') }.to raise_error(described_class::AuthError, /No Voice sign-in/)
  end

  it 'keeps only the session cookies' do
    allow(GMCP::Voice::Chrome).to receive(:cookies).and_return('SAPISID' => 's', 'NID' => 'n', 'OTHER' => 'x')

    expect(described_class.for('me@example.com').send(:cookie_header)).to eq('SAPISID=s; NID=n')
  end
end

describe GMCP::Voice::Tools do
  before { allow(GMCP::Server).to receive(:configured_account) { |account| account || 'me@example.com' } }
  after { described_class.reset_session! }

  def guard(account = nil)
    described_class.guarding(account) { |acct| described_class.session(acct).call('account/get') }
  end

  it 'drops the memoized session on an auth failure so the next call fetches a fresh one' do
    stale = instance_double(GMCP::Voice::Session)
    fresh = instance_double(GMCP::Voice::Session)
    allow(stale).to receive(:call).and_raise(GMCP::Voice::Session::AuthError, 'HTTP 401')
    allow(GMCP::Voice::Session).to receive(:for).and_return(stale, fresh)

    response = guard

    expect(response.error?).to be(true)
    expect(response.content.first[:text]).to match(/Voice auth failed for me@example.com: HTTP 401/)
    expect(described_class.session('me@example.com')).to be(fresh)
  end

  it 'keeps the session across ordinary API errors' do
    session = instance_double(GMCP::Voice::Session)
    allow(session).to receive(:call).and_raise(GMCP::Voice::Session::OperationError, 'HTTP 400')
    allow(GMCP::Voice::Session).to receive(:for).and_return(session)

    expect(guard.error?).to be(true)
    expect(described_class.session('me@example.com')).to be(session)
    expect(GMCP::Voice::Session).to have_received(:for).once
  end

  it 'keeps a separate session per account' do
    a = instance_double(GMCP::Voice::Session)
    b = instance_double(GMCP::Voice::Session)
    allow(GMCP::Voice::Session).to receive(:for).with('a@example.com').and_return(a)
    allow(GMCP::Voice::Session).to receive(:for).with('b@example.com').and_return(b)

    expect([described_class.session('a@example.com'), described_class.session('b@example.com')]).to eq([a, b])
  end
end

describe GMCP::Server, '.configured_account' do
  before do
    registry = GMCP::AccountRegistry.allocate
    registry.instance_variable_set(:@accounts, %w[a@example.com b@example.com])
    allow(described_class).to receive(:registry).and_return(registry)
  end

  it 'defaults to the first configured account' do
    expect(described_class.configured_account(nil)).to eq('a@example.com')
  end

  it 'refuses an account outside GMCP_ACCOUNTS' do
    expect { described_class.configured_account('x@example.com') }.to raise_error(ArgumentError, /Unknown account/)
  end
end
