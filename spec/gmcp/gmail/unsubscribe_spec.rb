# frozen_string_literal: true

require 'spec_helper'

describe GMCP::Gmail::Unsubscribe do
  def stub_headers(pairs)
    allow(GMCP::Gmail::Message).to receive(:get_raw) do |_path, _params, &blk|
      blk.call({ data: { payload: { headers: pairs.map { |n, v| { name: n, value: v } } } } }, nil)
    end
  end

  describe '.info' do
    it 'separates the https, http and mailto entries' do
      stub_headers([['List-Unsubscribe', '<mailto:x@y.z>, <https://ex.com/u/abc>'],
                    ['List-Unsubscribe-Post', 'List-Unsubscribe=One-Click']])
      i = described_class.info('m1')
      expect(i[:https]).to eq('https://ex.com/u/abc')
      expect(i[:mailto]).to eq('mailto:x@y.z')
      expect(i[:one_click]).to be(true)
    end

    it 'reports one_click false when the sender does not advertise it' do
      stub_headers([['List-Unsubscribe', '<https://ex.com/u>']])
      expect(described_class.info('m1')[:one_click]).to be(false)
    end

    it 'returns nil when there is no List-Unsubscribe header at all' do
      stub_headers([['Subject', 'hi']])
      expect(described_class.info('m1')).to be_nil
    end

    it 'parses a bare comma-separated header with no angle brackets' do
      stub_headers([['List-Unsubscribe', 'https://ex.com/u']])
      expect(described_class.info('m1')[:https]).to eq('https://ex.com/u')
    end

    it 'returns the header exactly as sent' do
      header = '<mailto:x@y.z?subject=unsub>, <https://ex.com/u/abc>'
      stub_headers([['List-Unsubscribe', header]])
      expect(described_class.info('m1')[:raw]).to eq(header)
    end

    it 'splits and trims a bracketless list with several entries' do
      stub_headers([['List-Unsubscribe', ' mailto:x@y.z ,  https://ex.com/u ']])
      i = described_class.info('m1')
      expect(i[:mailto]).to eq('mailto:x@y.z')
      expect(i[:https]).to eq('https://ex.com/u')
    end

    it 'keeps commas inside a bracketed URI' do
      stub_headers([['List-Unsubscribe', '<https://ex.com/u?a=1,2>']])
      expect(described_class.info('m1')[:https]).to eq('https://ex.com/u?a=1,2')
    end

    it 'matches the header names case-insensitively' do
      stub_headers([['list-unsubscribe', '<https://ex.com/u>'], ['LIST-UNSUBSCRIBE-POST', 'List-Unsubscribe=One-Click']])
      i = described_class.info('m1')
      expect(i[:https]).to eq('https://ex.com/u')
      expect(i[:one_click]).to be(true)
    end

    it 'treats a blank header as absent' do
      stub_headers([['List-Unsubscribe', '  ']])
      expect(described_class.info('m1')).to be_nil
    end

    it 'fetches only the two headers it reads' do
      google.get('/gmail/v1/users/me/messages/m1') do |env|
        expect(env.url.query).to include('format=metadata', 'metadataHeaders=List-Unsubscribe',
                                         'metadataHeaders=List-Unsubscribe-Post', 'fields=')
        json(payload: { headers: [{ name: 'List-Unsubscribe', value: '<https://ex.com/u>' }] })
      end
      expect(with_google { described_class.info('m1') }[:https]).to eq('https://ex.com/u')
    end

    it 'keeps a plaintext http entry visible rather than hiding it' do
      stub_headers([['List-Unsubscribe', '<http://ex.com/u>']])
      i = described_class.info('m1')
      expect(i[:http]).to eq('http://ex.com/u')
      expect(i[:https]).to be_nil
    end
  end

  describe '.one_click!' do
    it 'refuses when the sender does not advertise List-Unsubscribe-Post' do
      stub_headers([['List-Unsubscribe', '<https://ex.com/u>']])
      expect { described_class.one_click!('m1') }
        .to raise_error(described_class::NotSupported, /does not advertise/)
    end

    it 'refuses a mailto-only sender' do
      stub_headers([['List-Unsubscribe', '<mailto:x@y.z>'],
                    ['List-Unsubscribe-Post', 'List-Unsubscribe=One-Click']])
      expect { described_class.one_click!('m1') }
        .to raise_error(described_class::NotSupported, /mailto only/)
    end

    it 'refuses to downgrade to a plaintext http endpoint' do
      stub_headers([['List-Unsubscribe', '<http://ex.com/u>'],
                    ['List-Unsubscribe-Post', 'List-Unsubscribe=One-Click']])
      expect { described_class.one_click!('m1') }
        .to raise_error(described_class::NotSupported, /plaintext http/)
    end

    it 'refuses when the message has no List-Unsubscribe header' do
      stub_headers([['Subject', 'hi']])
      expect { described_class.one_click!('m1') }
        .to raise_error(described_class::NotSupported, /no List-Unsubscribe/)
    end

    it 'POSTs the RFC 8058 body to the https URL from the header' do
      stub_headers([['List-Unsubscribe', '<https://ex.com/u/abc>'],
                    ['List-Unsubscribe-Post', 'List-Unsubscribe=One-Click']])
      captured = nil
      allow(Net::HTTP).to receive(:start) do |host, _port, **_opts, &blk|
        expect(host).to eq('ex.com')
        fake = double('http')
        allow(fake).to receive(:request) { |req| captured = req; double('resp', code: '200').tap { |r| allow(r).to receive(:is_a?) { |k| k == Net::HTTPSuccess } } }
        blk.call(fake)
      end
      expect(described_class.one_click!('m1')).to eq('200')
      expect(captured.body).to eq('List-Unsubscribe=One-Click')
      expect(captured['content-type']).to eq('application/x-www-form-urlencoded')
    end

    it 'raises Failed on a non-success status rather than reporting success' do
      stub_headers([['List-Unsubscribe', '<https://ex.com/u>'],
                    ['List-Unsubscribe-Post', 'List-Unsubscribe=One-Click']])
      allow(Net::HTTP).to receive(:start) do |_h, _p, **_o, &blk|
        fake = double('http')
        allow(fake).to receive(:request).and_return(
          double('resp', code: '500').tap { |r| allow(r).to receive(:is_a?).and_return(false) }
        )
        blk.call(fake)
      end
      expect { described_class.one_click!('m1') }.to raise_error(described_class::Failed, /HTTP 500/)
    end
  end
end
