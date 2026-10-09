# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'digest'

describe GMCP::Voice::Chrome do
  let(:key) { OpenSSL::PKCS5.pbkdf2_hmac_sha1('peanuts', 'saltysalt', 1003, 16) }

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      original = ENV.fetch('GMCP_CHROME_DIR', nil)
      ENV['GMCP_CHROME_DIR'] = dir
      example.run
    ensure
      original ? ENV['GMCP_CHROME_DIR'] = original : ENV.delete('GMCP_CHROME_DIR')
      described_class.reset!
    end
  end

  before { allow(described_class).to receive(:key).and_return(key) }

  def encrypt(host, value, version: 24)
    plain = version >= 24 ? Digest::SHA256.digest(host) + value : value
    cipher = OpenSSL::Cipher.new('aes-128-cbc').encrypt
    cipher.key = key
    cipher.iv = ' ' * 16
    'v10'.b + cipher.update(plain) + cipher.final
  end

  # A Chrome user-data directory with one profile per { email => cookies }.
  def chrome(profiles = {}, version: 24, **by_email)
    profiles = profiles.merge(by_email)
    info = {}
    profiles.each_with_index do |(email, cookies), i|
      name = "Profile #{i + 1}"
      info[name] = { 'user_name' => email }
      FileUtils.mkdir_p(File.join(@dir, name))
      rows = cookies.map do |c|
        hex = encrypt(c[:host], c[:value], version:).unpack1('H*')
        "INSERT INTO cookies VALUES ('#{c[:host]}', '#{c[:name]}', X'#{hex}', #{c.fetch(:expires, 0)});"
      end
      sql = "CREATE TABLE meta (key TEXT, value TEXT); INSERT INTO meta VALUES ('version', '#{version}');" \
            'CREATE TABLE cookies (host_key TEXT, name TEXT, encrypted_value BLOB, expires_utc INTEGER);' + rows.join
      system('sqlite3', File.join(@dir, name, 'Cookies'), sql, exception: true)
    end
    File.write(File.join(@dir, 'Local State'), JSON.generate(profile: { info_cache: info }))
  end

  def chrome_time(time)
    (time.to_i + described_class::CHROME_EPOCH_OFFSET) * 1_000_000
  end

  it "reads and decrypts the google.com cookies of the account's own profile" do
    chrome('a@example.com' => [{ host: '.google.com', name: 'SAPISID', value: 'a-sapisid' }],
           'b@example.com' => [{ host: '.google.com', name: 'SAPISID', value: 'b-sapisid' }])

    expect(described_class.cookies('B@example.com')).to eq('SAPISID' => 'b-sapisid')
  end

  it 'reads databases older than version 24, which have no host digest' do
    chrome({ 'a@example.com' => [{ host: '.google.com', name: 'SID', value: 'old' }] }, version: 23)

    expect(described_class.cookies('a@example.com')).to eq('SID' => 'old')
  end

  it 'skips expired cookies and prefers the shared domain on a name clash' do
    chrome('a@example.com' => [
      { host: '.google.com', name: 'SID', value: 'shared' },
      { host: 'accounts.google.com', name: 'SID', value: 'host' },
      { host: '.google.com', name: 'OLD', value: 'x', expires: chrome_time(Time.now - 60) },
      { host: '.google.com', name: 'NEW', value: 'y', expires: chrome_time(Time.now + 60) }
    ])

    expect(described_class.cookies('a@example.com')).to eq('SID' => 'shared', 'NEW' => 'y')
  end

  it 'says so when no Chrome profile is signed in as the account' do
    chrome('a@example.com' => [])

    expect { described_class.cookies('z@example.com') }.to raise_error(described_class::Error, /No Chrome profile is signed in as z@example.com/)
  end

  it 'reports a wrong key as an Error rather than a cipher exception' do
    chrome('a@example.com' => [{ host: '.google.com', name: 'SID', value: 'v' }])
    allow(described_class).to receive(:key).and_return(OpenSSL::Random.random_bytes(16))

    expect { described_class.cookies('a@example.com') }.to raise_error(described_class::Error, /decrypt/)
  end
end
