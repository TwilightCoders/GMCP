# frozen_string_literal: true

require 'spec_helper'

describe GMCP::ApiBinding do
  let(:api_a) { { gmail: :gmail_a, calendar: :cal_a, drive: :drive_a } }
  let(:api_b) { { gmail: :gmail_b, calendar: :cal_b, drive: :drive_b } }

  around do |ex|
    saved = GMCP::Gmail::Message.instance_variable_get(:@_her_use_api)
    described_class.reset!
    ex.run
  ensure
    described_class.reset!
    GMCP::Gmail::Message.instance_variable_set(:@_her_use_api, saved)
  end

  describe '.install!' do
    it 'binds a resolver rather than a concrete API' do
      described_class.install!
      bound = GMCP::Gmail::Message.instance_variable_get(:@_her_use_api)
      expect(bound).to respond_to(:call)
    end

    it 'is idempotent' do
      described_class.install!
      first = GMCP::Gmail::Message.instance_variable_get(:@_her_use_api)
      described_class.install!
      expect(GMCP::Gmail::Message.instance_variable_get(:@_her_use_api)).to equal(first)
    end

    it 'resolves through him at call time, not at bind time' do
      described_class.install!
      described_class.current = api_a
      expect(GMCP::Gmail::Message.her_api).to eq(:gmail_a)
      described_class.current = api_b
      expect(GMCP::Gmail::Message.her_api).to eq(:gmail_b)
    end
  end

  describe '.fetch' do
    it 'raises rather than silently reusing a previous account when nothing is bound' do
      expect { described_class.fetch(:gmail) }.to raise_error(described_class::NotBound, /no account is bound/)
    end

    it 'raises when the bound account lacks that service' do
      described_class.current = { gmail: :g }
      expect { described_class.fetch(:drive) }.to raise_error(described_class::NotBound, /no drive API/)
    end
  end

  describe '.with' do
    it 'restores the previous binding afterwards' do
      described_class.current = api_a
      described_class.with(api_b) { expect(described_class.current).to eq(api_b) }
      expect(described_class.current).to eq(api_a)
    end

    it 'restores even when the block raises' do
      described_class.current = api_a
      expect { described_class.with(api_b) { raise 'boom' } }.to raise_error('boom')
      expect(described_class.current).to eq(api_a)
    end

    it 'restores to nil when nothing was bound before' do
      described_class.with(api_a) { nil }
      expect(described_class.current).to be_nil
    end

    it 'nests without leaking the inner account to the outer block' do
      seen = []
      described_class.with(api_a) do
        seen << described_class.current
        described_class.with(api_b) { seen << described_class.current }
        seen << described_class.current
      end
      expect(seen).to eq([api_a, api_b, api_a])
    end
  end

  # The reason this module exists. Under the previous implementation — which
  # wrote the API onto the model class — these threads would race on process
  # global state and at least one would read the other's account.
  describe 'concurrent isolation' do
    it 'keeps two accounts separate across interleaved threads' do
      described_class.install!
      observed = {}

      threads = [[:a, api_a, :gmail_a], [:b, api_b, :gmail_b]].map do |name, apis, expected|
        Thread.new do
          described_class.with(apis) do
            # Interleave deliberately: yield the scheduler between binding and
            # reading, which is exactly when a shared global gets clobbered.
            10.times do
              Thread.pass
              sleep 0.001
              observed[name] ||= []
              observed[name] << (GMCP::Gmail::Message.her_api == expected)
            end
          end
        end
      end
      threads.each(&:join)

      expect(observed[:a]).to all(be(true))
      expect(observed[:b]).to all(be(true))
      expect(observed[:a].length).to eq(10)
      expect(observed[:b].length).to eq(10)
    end

    it 'leaves no binding behind in a thread that finished' do
      described_class.install!
      t = Thread.new { described_class.with(api_a) { :done } }
      t.join
      expect(described_class.current).to be_nil
    end
  end
end
