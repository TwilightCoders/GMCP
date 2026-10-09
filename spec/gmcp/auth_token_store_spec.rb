# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'yaml/store'

describe GMCP::Auth::TokenStore do
  around { |example| Dir.mktmpdir { |dir| @dir = dir; example.run } }

  let(:path)  { File.join(@dir, 'acct@example.com', 'token.yaml') }
  let(:store) { described_class.new(path) }

  it 'reads nothing, and creates nothing, for an account never authorized' do
    expect(store.load('acct@example.com')).to be_nil
    expect(File.exist?(File.dirname(path))).to be(false)
  end

  it 'writes the token owner-only, in an owner-only directory' do
    store.store('acct@example.com', '{"refresh_token":"r"}')

    expect(File.stat(path).mode & 0o777).to eq(0o600)
    expect(File.stat(File.dirname(path)).mode & 0o777).to eq(0o700)
    expect(store.load('acct@example.com')).to eq('{"refresh_token":"r"}')
  end

  it 'reads files written by googleauth FileTokenStore' do
    FileUtils.mkdir_p(File.dirname(path))
    YAML::Store.new(path).transaction { |s| s['acct@example.com'] = '{"a":1}' }

    expect(store.load('acct@example.com')).to eq('{"a":1}')
  end

  it 'tightens an older world-readable token file when it reads it' do
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, YAML.dump('acct@example.com' => 't'), perm: 0o644)

    store.load('acct@example.com')

    expect(File.stat(path).mode & 0o777).to eq(0o600)
  end

  it 'deletes one id and keeps the rest' do
    store.store('a', '1')
    store.store('b', '2')
    store.delete('a')

    expect([store.load('a'), store.load('b')]).to eq([nil, '2'])
  end
end

describe GMCP::Auth do
  describe '.token_path' do
    it 'rejects anything that is not a plain email address' do
      ['../../.ssh', 'a/b@c.com', 'nobody', '', nil, 'a b@c.com'].each do |bad|
        expect { described_class.token_path(bad) }.to raise_error(ArgumentError), bad.inspect
      end
    end
  end

  describe '.credentials' do
    after { described_class.reset! }

    it 'raises AuthRequired without touching disk for an account never authorized' do
      account = "never-#{SecureRandom.hex(4)}@example.invalid"

      expect { described_class.credentials(account:) }.to raise_error(described_class::AuthRequired)
      expect(File.exist?(File.dirname(described_class.token_path(account)))).to be(false)
    end
  end
end
