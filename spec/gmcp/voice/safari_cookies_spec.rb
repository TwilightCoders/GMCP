# frozen_string_literal: true

require 'spec_helper'

describe GMCP::Voice::SafariCookies do
  describe '.read on a host that cannot supply cookies' do
    it 'refuses on a non-macOS host with an explanation, not a file error' do
      stub_const('RbConfig::CONFIG', RbConfig::CONFIG.merge('host_os' => 'linux-gnu'))
      expect { described_class.read(domain: '.google.com') }
        .to raise_error(described_class::Unavailable, /only works on macOS/)
    end

    it 'names the missing path when Safari has no cookie store' do
      stub_const('RbConfig::CONFIG', RbConfig::CONFIG.merge('host_os' => 'darwin24'))
      expect { described_class.read(domain: '.google.com', path: '/nope/Cookies.binarycookies') }
        .to raise_error(described_class::Unavailable, %r{/nope/Cookies\.binarycookies})
    end
  end

  describe '.available?' do
    it 'is false off macOS regardless of any file present' do
      stub_const('RbConfig::CONFIG', RbConfig::CONFIG.merge('host_os' => 'linux-gnu'))
      expect(described_class.available?).to be(false)
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
