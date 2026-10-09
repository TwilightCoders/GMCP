# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

# Builds a minimal Cookies.binarycookies image. Each cookie is
# { url:, name:, value:, expiry: <Time or nil> }; a nil expiry is stored as 0.
module BinaryCookiesFixture
  MAC_EPOCH = GMCP::Voice::SafariCookies::MAC_EPOCH_OFFSET

  def self.cookie_record(url:, name:, value:, path: '/', expiry: nil)
    strings = [url, name, path, value].map { |s| "#{s}\x00".b }
    offsets = []
    cursor = 56
    strings.each do |s|
      offsets << cursor
      cursor += s.bytesize
    end
    expiry_mac = expiry ? expiry.to_f - MAC_EPOCH : 0.0
    header = [cursor, 0, 0, 0, *offsets].pack('L<8') + ("\x00" * 8).b + [expiry_mac, 0.0].pack('EE')
    header + strings.join
  end

  def self.page(cookies)
    records = cookies.map { |c| cookie_record(**c) }
    head_size = 8 + (records.size * 4) + 4
    offsets = []
    cursor = head_size
    records.each do |r|
      offsets << cursor
      cursor += r.bytesize
    end
    [0x00000100].pack('L>') + [records.size].pack('L<') + offsets.pack('L<*') + [0].pack('L<') + records.join
  end

  def self.file(*pages_of_cookies)
    pages = pages_of_cookies.map { |cookies| page(cookies) }
    'cook'.b + [pages.size].pack('L>') + pages.map(&:bytesize).pack('L>*') + pages.join
  end
end

describe GMCP::Voice::SafariCookies do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  before { stub_const('RbConfig::CONFIG', RbConfig::CONFIG.merge('host_os' => 'darwin24')) }

  def store(bytes)
    path = File.join(@dir, 'Cookies.binarycookies')
    File.binwrite(path, bytes)
    path
  end

  let(:future) { Time.now + 86_400 }
  let(:past)   { Time.now - 86_400 }

  describe '.read on a host that cannot supply cookies' do
    it 'refuses on a non-macOS host with an explanation, not a file error' do
      stub_const('RbConfig::CONFIG', RbConfig::CONFIG.merge('host_os' => 'linux-gnu'))
      expect { described_class.read(domain: '.google.com') }
        .to raise_error(described_class::Unavailable, /only works on macOS/)
    end

    it 'names the missing path when Safari has no cookie store' do
      expect { described_class.read(domain: '.google.com', path: '/nope/Cookies.binarycookies') }
        .to raise_error(described_class::Unavailable, %r{/nope/Cookies\.binarycookies})
    end

    it 'turns a privacy-control denial into an actionable Full Disk Access hint' do
      allow(File).to receive(:binread).and_raise(Errno::EPERM)
      expect { described_class.read(domain: '.google.com') }
        .to raise_error(described_class::Unavailable, /Full Disk Access/)
    end

    it 'treats EACCES the same way' do
      allow(File).to receive(:binread).and_raise(Errno::EACCES)
      expect { described_class.read(domain: '.google.com') }
        .to raise_error(described_class::Unavailable, /Full Disk Access/)
    end
  end

  describe 'store location' do
    it 'prefers the sandboxed container store over the legacy one' do
      expect(described_class::PATHS.first).to include('Containers/com.apple.Safari')
      expect(described_class::PATHS.last).to end_with('Library/Cookies/Cookies.binarycookies')
    end

    it 'falls back to the legacy store when the container has none' do
      container, legacy = described_class::PATHS
      bytes = BinaryCookiesFixture.file([{ url: '.google.com', name: 'SID', value: 'legacy' }])
      allow(File).to receive(:binread).with(container).and_raise(Errno::ENOENT)
      allow(File).to receive(:binread).with(legacy).and_return(bytes)
      expect(described_class.read(domain: '.google.com')).to eq('SID' => 'legacy')
    end

    it 'reads the legacy store when the container is denied but the legacy one is readable' do
      container, legacy = described_class::PATHS
      bytes = BinaryCookiesFixture.file([{ url: '.google.com', name: 'SID', value: 'legacy' }])
      allow(File).to receive(:binread).with(container).and_raise(Errno::EPERM)
      allow(File).to receive(:binread).with(legacy).and_return(bytes)
      expect(described_class.read(domain: '.google.com')).to eq('SID' => 'legacy')
    end
  end

  describe 'parsing' do
    it 'reads cookies for the requested domain across pages, ignoring others' do
      path = store(BinaryCookiesFixture.file(
        [{ url: '.google.com', name: 'SID', value: 'sid-value' },
         { url: '.example.com', name: 'SID', value: 'not-google' }],
        [{ url: 'google.com', name: 'HSID', value: 'hsid-value', expiry: future }]
      ))
      expect(described_class.read(domain: '.google.com', path: path))
        .to eq('SID' => 'sid-value', 'HSID' => 'hsid-value')
    end

    it 'filters to the requested names' do
      path = store(BinaryCookiesFixture.file(
        [{ url: '.google.com', name: 'SID', value: 'a' }, { url: '.google.com', name: 'NID', value: 'b' }]
      ))
      expect(described_class.read(domain: '.google.com', names: ['NID'], path: path)).to eq('NID' => 'b')
    end

    it 'skips expired cookies' do
      path = store(BinaryCookiesFixture.file([{ url: '.google.com', name: 'SID', value: 'old', expiry: past }]))
      expect(described_class.read(domain: '.google.com', path: path)).to eq({})
    end

    it 'prefers the unexpired duplicate with the latest expiry, whatever the order' do
      path = store(BinaryCookiesFixture.file(
        [{ url: '.google.com', name: 'SID', value: 'later', expiry: future + 3600 },
         { url: '.google.com', name: 'SID', value: 'sooner', expiry: future }],
        [{ url: '.google.com', name: 'SID', value: 'expired', expiry: past }]
      ))
      expect(described_class.read(domain: '.google.com', path: path)).to eq('SID' => 'later')
    end

    it 'rejects a file without the binarycookies magic' do
      path = store('nope' * 4)
      expect { described_class.read(domain: '.google.com', path: path) }
        .to raise_error(described_class::ParseError, /Bad magic/)
    end

    it 'raises ParseError, not NoMethodError, on a truncated store' do
      bytes = BinaryCookiesFixture.file([{ url: '.google.com', name: 'SID', value: 'x' }])
      [bytes.bytesize - 5, 60, 20, 9].each do |cut|
        path = store(bytes.byteslice(0, cut))
        expect { described_class.read(domain: '.google.com', path: path) }
          .to raise_error(described_class::ParseError), "cut at #{cut}"
      end
    end

    it 'raises ParseError when a string offset points outside its record' do
      bytes = BinaryCookiesFixture.file([{ url: '.google.com', name: 'SID', value: 'x' }]).dup
      page_start = 8 + 4
      cookie_start = page_start + 8 + 4 + 4
      bytes[cookie_start + 20, 4] = [9_999].pack('L<')
      path = store(bytes)
      expect { described_class.read(domain: '.google.com', path: path) }
        .to raise_error(described_class::ParseError, /outside/)
    end

    it 'raises ParseError when a cookie record claims to run past its page' do
      bytes = BinaryCookiesFixture.file([{ url: '.google.com', name: 'SID', value: 'x' }]).dup
      cookie_start = 8 + 4 + 8 + 4 + 4
      bytes[cookie_start, 4] = [9_999].pack('L<')
      path = store(bytes)
      expect { described_class.read(domain: '.google.com', path: path) }
        .to raise_error(described_class::ParseError, /truncated/)
    end
  end
end

describe GMCP::Voice::Session do
  it 'reports an unavailable cookie store as AuthError, so the tool layer can render it' do
    allow(GMCP::Voice::SafariCookies).to receive(:read)
      .and_raise(GMCP::Voice::SafariCookies::Unavailable, 'no cookies here')
    expect { described_class.new }.to raise_error(described_class::AuthError, /no cookies here/)
  end

  it 'reports a corrupt cookie store as AuthError too' do
    allow(GMCP::Voice::SafariCookies).to receive(:read)
      .and_raise(GMCP::Voice::SafariCookies::ParseError, 'Bad magic')
    expect { described_class.new }.to raise_error(described_class::AuthError, /Bad magic/)
  end

  it 'still rejects a cookie set with no SAPISID' do
    expect { described_class.new(cookies: { 'SID' => 'x' }) }
      .to raise_error(described_class::AuthError, /SAPISID/)
  end
end
