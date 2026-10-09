# frozen_string_literal: true

require 'spec_helper'

describe 'Gmail search' do
  def stub_message(id, from:, subject:, date: 'Wed, 1 Oct 2026 09:00:00 -0600')
    google.get("/gmail/v1/users/me/messages/#{id}") do |env|
      expect(env.url.query).to include('format=metadata', 'metadataHeaders=From', 'fields=')
      json(id: id, payload: { headers: [{ name: 'From', value: from },
                                        { name: 'Subject', value: subject },
                                        { name: 'Date', value: date }] })
    end
  end

  describe GMCP::Gmail::Message, '.metadata_for' do
    let(:ids) { Array.new(20) { |i| "m#{i}" } }

    before { ids.each { |id| stub_message(id, from: "#{id}@x", subject: "s-#{id}") } }

    # Each worker thread starts unbound; without rebinding the caller's
    # account every fetch would raise ApiBinding::NotBound.
    it 'fetches every id on worker threads bound to the caller’s account' do
      found = with_google { described_class.metadata_for(ids, headers: %w[From Subject Date]) }
      expect(found.map { |m| m.header('From') }).to eq(ids.map { |id| "#{id}@x" })
    end

    it 'keeps the order it was given, whatever order the fetches finish in' do
      found = with_google { described_class.metadata_for(ids.reverse, headers: %w[From]) }
      expect(found.map(&:id)).to eq(ids.reverse)
    end

    it 'does not leak the binding into the caller once done' do
      with_google { described_class.metadata_for(ids.first(2), headers: %w[From]) }
      expect(GMCP::ApiBinding.current).to be_nil
    end

    it 'returns an empty list without starting any threads' do
      expect(Thread).not_to receive(:new)
      expect(with_google { described_class.metadata_for([], headers: %w[From]) }).to eq([])
    end

    it 'keeps a message deleted since the listing as a bare id' do
      google.get('/gmail/v1/users/me/messages/gone') { json({ error: { message: 'Not Found' } }, status: 404) }
      found = with_google { described_class.metadata_for(%w[m0 gone m1], headers: %w[From]) }
      expect(found.map(&:id)).to eq(%w[m0 gone m1])
      expect(found[1].headers).to eq({})
    end

    it 'raises any other failure to the caller' do
      google.get('/gmail/v1/users/me/messages/bad') { json({ error: { message: 'Rate limited' } }, status: 429) }
      expect { with_google { described_class.metadata_for(%w[m0 bad], headers: %w[From]) } }
        .to raise_error(GMCP::ApiError, /Rate limited/)
    end
  end

  describe GMCP::Gmail::Tools, '.search' do
    def text_of(response)
      response.content.first[:text]
    end

    it 'returns one line per message with date, sender and subject' do
      google.get('/gmail/v1/users/me/messages') do |env|
        expect(env.url.query).to include('q=from%3Aalice')
        json(messages: [{ id: 'a1' }, { id: 'a2' }], nextPageToken: 'NEXT', resultSizeEstimate: 40)
      end
      stub_message('a1', from: 'Alice <alice@x>', subject: 'Lunch')
      stub_message('a2', from: 'Alice <alice@x>', subject: 'Dinner', date: 'Thu, 2 Oct 2026 18:00:00 -0600')

      text = text_of(with_google { described_class.search(query: 'from:alice') })
      expect(text.lines.first(2).map(&:chomp)).to eq([
        'a1  Wed, 1 Oct 2026 09:00:00 -0600  Alice <alice@x>  Lunch',
        'a2  Thu, 2 Oct 2026 18:00:00 -0600  Alice <alice@x>  Dinner'
      ])
      expect(text).to include('next page_token: NEXT', '~40 total matches')
    end

    it 'says so when nothing matches, without fetching anything' do
      google.get('/gmail/v1/users/me/messages') { json(resultSizeEstimate: 0) }
      expect(text_of(with_google { described_class.search(query: 'nothing') })).to start_with('No messages found.')
    end
  end
end
