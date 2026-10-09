# frozen_string_literal: true

require 'spec_helper'
require 'net/http'

describe GMCP::Auth, '.authorize_interactive!' do
  let(:failures) { Queue.new }

  before do
    allow(described_class).to receive(:client_id).and_return(Google::Auth::ClientId.new('client-id', 'secret'))
    allow(described_class).to receive(:open_browser)
  end

  after { described_class.reset! }

  def start
    url = described_class.authorize_interactive!(
      account: 'acct@example.com', timeout: 5,
      on_success: ->(_) {}, on_failure: ->(_, e) { failures << e }
    )
    params = URI.decode_www_form(URI(url).query).to_h
    [URI(params.fetch('redirect_uri')), params]
  end

  def hit(callback, query)
    Net::HTTP.get_response(URI("#{callback}?#{URI.encode_www_form(query)}"))
  end

  it 'listens on loopback only and pre-selects the account' do
    callback, params = start

    expect(callback.host).to eq('127.0.0.1')
    expect(params['login_hint']).to eq('acct@example.com')
    expect(params['state']).not_to be_empty
  end

  it 'ignores a request without the right state and keeps waiting' do
    callback, params = start

    expect(hit(callback, code: 'forged').code).to eq('400')
    expect(hit(callback, code: 'forged', state: 'wrong').code).to eq('400')
    expect(failures).to be_empty

    expect(hit(callback, state: params['state'], error: 'access_denied').code).to eq('200')
    expect(failures.pop(timeout: 2).message).to eq('access_denied')
  end

  it 'refuses an account that is not an email address before opening anything' do
    expect { described_class.authorize_interactive!(account: '../x', on_success: ->(_) {}) }
      .to raise_error(ArgumentError)
    expect(described_class).not_to have_received(:open_browser)
  end
end
