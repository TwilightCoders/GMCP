# frozen_string_literal: true

require 'spec_helper'

# api2thread/list responses in the positional shape the API returns. Every
# number is in the reserved 555-01xx range and every string is invented.
module VoiceListFixture
  def self.text_thread(number:, texts:, read: true, newest_ms: 1_760_000_000_000)
    messages = texts.each_with_index.map do |(type, body), i|
      ["msg-#{number}-#{i}", (newest_ms - (i * 60_000)).to_s, nil, ['', number], type, 1, nil, nil, nil, body]
    end
    ["t.#{number}", read, messages, 'page-token', [['Pat Example', number]], [2], nil, true, [number]]
  end

  def self.voicemail_thread(number:, newest_ms:)
    transcript = [0.9, [['SGVsbG8='], ['d29ybGQ=']]] # "Hello", "world"
    message = ['vm-1', newest_ms.to_s, nil, [nil, number], 2, 0, transcript, nil, 31.5]
    ['c.opaque-voicemail', false, [message], nil, [], [4], nil, false, [number]]
  end

  def self.response(*threads)
    [threads, nil, 'version-token']
  end
end

describe GMCP::Voice::Folder do
  let(:session) { instance_double(GMCP::Voice::Session) }

  let(:page) do
    VoiceListFixture.response(
      VoiceListFixture.text_thread(number: '+15550100', texts: [[10, 'See you at noon'], [11, 'Lunch?']],
                                   newest_ms: 1_760_000_000_000),
      VoiceListFixture.voicemail_thread(number: '+15550199', newest_ms: 1_759_000_000_000)
    )
  end

  describe '.fetch' do
    it 'asks api2thread/list for the folder in the web client request shape' do
      allow(session).to receive(:call).and_return(page)
      described_class.fetch(session, 'voicemail', cursor: 1_759_000_000_000)
      expect(session).to have_received(:call)
        .with('api2thread/list', [4, 20, 15, '1759000000000', nil, [nil, 1, 1, 1]])
    end

    it 'defaults to the unified folder with no cursor' do
      allow(session).to receive(:call).and_return(page)
      described_class.fetch(session)
      expect(session).to have_received(:call).with('api2thread/list', [1, 20, 15, nil, nil, [nil, 1, 1, 1]])
    end

    it 'rejects an unknown folder before calling the API' do
      allow(session).to receive(:call)
      expect { described_class.fetch(session, 'starred') }.to raise_error(ArgumentError, /Valid: all, messages/)
      expect(session).not_to have_received(:call)
    end
  end

  describe 'response parsing' do
    subject(:folder) do
      allow(session).to receive(:call).and_return(page)
      described_class.fetch(session, 'all')
    end

    it 'decodes threads and their newest-first messages' do
      text, voicemail = folder.conversations
      expect(text.id).to eq('t.+15550100')
      expect(text.read?).to be(true)
      expect(text.latest.type_name).to eq('sms.received')
      expect(text.latest.text).to eq('See you at noon')
      expect(text.latest.time).to eq(Time.at(1_760_000_000))
      expect(text.counterparty).to eq('Pat Example +15550100')

      expect(voicemail.read?).to be(false)
      expect(voicemail.latest.type_name).to eq('voicemail')
      expect(voicemail.latest.duration).to eq(31.5)
      expect(voicemail.latest.text).to eq('Hello world')
      expect(voicemail.phone_numbers).to eq(['+15550199'])
    end

    it 'derives the next cursor from the last thread on the page' do
      expect(folder.next_cursor).to eq('1759000000000')
    end

    it 'treats an empty or unexpected body as an empty page' do
      [[], nil, {}, [nil]].each do |body|
        allow(session).to receive(:call).and_return(body)
        empty = described_class.fetch(session)
        expect(empty.conversations).to eq([])
        expect(empty.next_cursor).to be_nil
      end
    end

    it 'skips rows that are not threads' do
      allow(session).to receive(:call).and_return([[nil, 'junk', [], page[0][0]]])
      expect(described_class.fetch(session).conversations.map(&:id)).to eq(['t.+15550100'])
    end
  end

  describe '.search' do
    let(:second_page) do
      VoiceListFixture.response(
        VoiceListFixture.text_thread(number: '+15550142', texts: [[11, 'The invoice is attached']],
                                     newest_ms: 1_758_000_000_000)
      )
    end

    before do
      allow(session).to receive(:call).and_return(page, second_page, VoiceListFixture.response)
    end

    it 'matches message text across pages, following the cursor' do
      matches, scanned = described_class.search(session, 'INVOICE')
      expect(matches.map(&:id)).to eq(['t.+15550142'])
      expect(scanned).to eq(3)
      expect(session).to have_received(:call)
        .with('api2thread/list', [1, 20, 15, '1759000000000', nil, [nil, 1, 1, 1]])
    end

    it 'matches a formatted phone number by its digits' do
      matches, = described_class.search(session, '555-0199')
      expect(matches.map(&:id)).to eq(['c.opaque-voicemail'])
    end

    it 'matches contact names and voicemail transcripts' do
      expect(described_class.search(session, 'pat example').first.size).to eq(2)
      allow(session).to receive(:call).and_return(page, VoiceListFixture.response)
      expect(described_class.search(session, 'hello world').first.map(&:id)).to eq(['c.opaque-voicemail'])
    end

    it 'stops at the page limit' do
      described_class.search(session, 'nothing', pages: 1)
      expect(session).to have_received(:call).once
    end
  end
end

describe GMCP::Voice::Tools do
  it 'marks a thread read by setting only the read flag' do
    expect(described_class.mark_read_body('t.+15550100')).to eq(
      [['t.+15550100', nil, nil, true, nil, nil, nil, nil], [nil, nil, nil, true, nil, nil, nil, nil], 1]
    )
  end

  it 'formats a thread as one line with id, type, counterparty, time and preview' do
    row = VoiceListFixture.text_thread(number: '+15550100', texts: [[11, "Running\nlate"]], read: false)
    line = described_class.format(GMCP::Voice::Conversation.from_jspb(row))
    expect(line).to start_with('t.+15550100 [sms.sent] Pat Example +15550100 ')
    expect(line).to end_with('read=false — Running late')
  end
end

describe GMCP::Voice::Tools, 'registered tools' do
  let(:server) { MCP::Server.new(name: 'test') }
  let(:session) { instance_double(GMCP::Voice::Session) }

  before do
    described_class.register(server)
    allow(GMCP::Server).to receive(:configured_account) { |account| account || 'me@example.com' }
    allow(GMCP::Voice::Session).to receive(:for).with('me@example.com').and_return(session)
  end

  after { described_class.reset_session! }

  def call(name, **args)
    server.tools.fetch(name).call(**args, server_context: nil)
  end

  it 'lists a folder page and hands back the cursor for the next one' do
    row = VoiceListFixture.text_thread(number: '+15550100', texts: [[10, 'Hi']], newest_ms: 1_760_000_000_000)
    allow(session).to receive(:call).and_return(VoiceListFixture.response(row))

    text = call('voice_list', folder: 'messages').content.first[:text]

    expect(text).to include('t.+15550100 [sms.received]')
    expect(text).to end_with('next_cursor: 1760000000000')
  end

  it 'reports an unknown folder as an isError response' do
    response = call('voice_list', folder: 'starred')
    expect(response.error?).to be(true)
    expect(response.content.first[:text]).to match(/Unknown folder: starred/)
  end

  it 'registers no archive or delete tool' do
    expect(server.tools.keys).to contain_exactly('voice_account', 'voice_list', 'voice_search', 'voice_mark_read')
  end
end
