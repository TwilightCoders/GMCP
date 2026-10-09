# frozen_string_literal: true

require 'spec_helper'

describe GMCP::Gmail::Message do
  let(:test_api) { Him::API.new(url: GMCP::Apis::GMAIL_BASE) }

  around do |ex|
    original = described_class.instance_variable_get(:@_her_use_api)
    described_class.use_api(test_api)
    ex.run
  ensure
    described_class.instance_variable_set(:@_her_use_api, original)
  end

  def stub_response(data)
    allow(test_api).to receive(:request)
      .and_return({ parsed_data: { data: data, errors: {}, metadata: {} }, response: double('r', success?: true) })
  end

  # ── pagination ───────────────────────────────────────────────────────────
  describe '.search_page' do
    it 'returns the cursor alongside the messages' do
      stub_response(messages: [{ id: 'a' }, { id: 'b' }], nextPageToken: 'TOK', resultSizeEstimate: 240)
      page = described_class.search_page('in:inbox', max_results: 2)
      expect(page[:messages].map(&:id)).to eq(%w[a b])
      expect(page[:next_page_token]).to eq('TOK')
      expect(page[:estimate]).to eq(240)
    end

    it 'sends the cursor back as pageToken' do
      stub_response(messages: [])
      described_class.search_page('in:inbox', page_token: 'TOK')
      expect(test_api).to have_received(:request)
        .with(hash_including(_method: :get, _path: 'messages', pageToken: 'TOK'))
    end

    it 'omits pageToken entirely on the first page' do
      stub_response(messages: [])
      described_class.search_page('in:inbox')
      expect(test_api).to have_received(:request) { |params| expect(params).not_to have_key(:pageToken) }
    end

    it 'omits an empty cursor rather than sending a blank one' do
      stub_response(messages: [])
      described_class.search_page('in:inbox', page_token: '')
      expect(test_api).to have_received(:request) { |params| expect(params).not_to have_key(:pageToken) }
    end

    it 'omits q when no query is given, so it can list a whole mailbox' do
      stub_response(messages: [])
      described_class.search_page(nil)
      expect(test_api).to have_received(:request) { |params| expect(params).not_to have_key(:q) }
    end

    it 'reports a nil cursor on the last page' do
      stub_response(messages: [{ id: 'z' }])
      expect(described_class.search_page('x')[:next_page_token]).to be_nil
    end

    it 'tolerates a response with no messages key at all' do
      stub_response({})
      page = described_class.search_page('x')
      expect(page[:messages]).to eq([])
      expect(page[:next_page_token]).to be_nil
    end
  end

  describe '.each_page' do
    it 'walks pages until the cursor runs out' do
      pages = [
        { messages: [{ id: 'a' }], nextPageToken: 't1' },
        { messages: [{ id: 'b' }], nextPageToken: 't2' },
        { messages: [{ id: 'c' }] }
      ]
      allow(test_api).to receive(:request) do
        { parsed_data: { data: pages.shift, errors: {}, metadata: {} }, response: double('r') }
      end
      expect(described_class.each_page('x').flat_map { |p| p[:messages].map(&:id) }).to eq(%w[a b c])
    end

    it 'stops at max_pages so a runaway cursor cannot spin forever' do
      allow(test_api).to receive(:request)
        .and_return({ parsed_data: { data: { messages: [{ id: 'a' }], nextPageToken: 'always' }, errors: {}, metadata: {} }, response: double('r') })
      expect(described_class.each_page('x', max_pages: 3).to_a.length).to eq(3)
    end

    it 'treats an empty-string cursor as the end, not as a further page' do
      allow(test_api).to receive(:request)
        .and_return({ parsed_data: { data: { messages: [{ id: 'a' }], nextPageToken: '' }, errors: {}, metadata: {} }, response: double('r') })
      expect(described_class.each_page('x', max_pages: 10).to_a.length).to eq(1)
    end

    it 'returns an Enumerator when called without a block' do
      expect(described_class.each_page('x')).to be_a(Enumerator)
    end
  end

  # ── batch ────────────────────────────────────────────────────────────────
  describe '.batch_modify' do
    before { stub_response({}) }

    it 'POSTs one request for the whole set' do
      described_class.batch_modify(ids: %w[a b c], add_label_ids: ['X'], remove_label_ids: ['Y'])
      expect(test_api).to have_received(:request).once.with(
        hash_including(_method: :post, _path: 'messages/batchModify',
                       ids: %w[a b c], addLabelIds: ['X'], removeLabelIds: ['Y'])
      )
    end

    it 'refuses an empty set rather than issuing a no-op request' do
      expect { described_class.batch_modify(ids: []) }.to raise_error(ArgumentError, /no message ids/)
      expect(test_api).not_to have_received(:request)
    end

    it "refuses a set over Gmail's limit rather than silently truncating" do
      ids = Array.new(described_class::BATCH_LIMIT + 1) { |i| "id#{i}" }
      expect { described_class.batch_modify(ids: ids) }.to raise_error(ArgumentError, /exceeds/)
      expect(test_api).not_to have_received(:request)
    end

    it 'accepts exactly the limit' do
      described_class.batch_modify(ids: Array.new(described_class::BATCH_LIMIT) { |i| "id#{i}" })
      expect(test_api).to have_received(:request).once
    end
  end

  describe 'batch convenience wrappers' do
    before { stub_response({}) }

    it 'trashes by adding the TRASH label, since there is no batchTrash endpoint' do
      described_class.batch_trash(ids: %w[a b])
      expect(test_api).to have_received(:request).with(
        hash_including(_path: 'messages/batchModify', ids: %w[a b], addLabelIds: ['TRASH'], removeLabelIds: [])
      )
    end

    it 'archives by removing INBOX and nothing else' do
      described_class.batch_archive(ids: %w[a b])
      expect(test_api).to have_received(:request).with(
        hash_including(_path: 'messages/batchModify', removeLabelIds: ['INBOX'], addLabelIds: [])
      )
    end
  end

  # ── attachments ──────────────────────────────────────────────────────────
  describe '.attachments' do
    it 'finds attachment parts nested at any depth' do
      stub_response(payload: {
        mimeType: 'multipart/mixed',
        parts: [
          { mimeType: 'text/plain', body: { size: 10 } },
          { mimeType: 'multipart/alternative',
            parts: [{ filename: 'deep.pdf', mimeType: 'application/pdf', body: { size: 99, attachmentId: 'A2' } }] },
          { filename: 'top.csv', mimeType: 'text/csv', body: { size: 5, attachmentId: 'A1' } }
        ]
      })
      found = described_class.attachments('m1')
      expect(found.map { |a| a[:filename] }).to contain_exactly('deep.pdf', 'top.csv')
      expect(found.find { |a| a[:filename] == 'deep.pdf' })
        .to include(attachment_id: 'A2', mime_type: 'application/pdf', size: 99)
    end

    it 'ignores body parts, which have no attachmentId' do
      stub_response(payload: { mimeType: 'text/plain', body: { size: 20 } })
      expect(described_class.attachments('m1')).to be_empty
    end

    it 'ignores inline parts that carry no filename' do
      stub_response(payload: { parts: [{ filename: '', mimeType: 'image/png', body: { attachmentId: 'INLINE' } }] })
      expect(described_class.attachments('m1')).to be_empty
    end

    it 'requests the full format, since metadata omits part structure' do
      stub_response(payload: {})
      described_class.attachments('m1')
      expect(test_api).to have_received(:request)
        .with(hash_including(_method: :get, _path: 'messages/m1', format: 'full'))
    end

    it 'returns empty for a message with no payload' do
      stub_response({})
      expect(described_class.attachments('m1')).to eq([])
    end

    it 'trims the response to the part tree with a fields mask' do
      stub_response(payload: {})
      described_class.attachments('m1')
      expect(test_api).to have_received(:request).with(hash_including(fields: described_class::ATTACHMENT_FIELDS))
    end
  end

  describe 'ATTACHMENT_FIELDS' do
    it 'reaches nested parts without selecting body data' do
      mask = described_class::ATTACHMENT_FIELDS
      expect(mask).to start_with('payload(partId,filename,mimeType,body(size,attachmentId),parts(')
      expect(mask.scan('parts(').length).to eq(10)
      expect(mask).not_to include('data')
      expect(mask.count('(')).to eq(mask.count(')'))
    end
  end

  describe '.collect_attachment_parts' do
    def collect(payload)
      described_class.send(:collect_attachment_parts, payload)
    end

    it 'reports the stable partId alongside the per-fetch attachmentId' do
      found = collect(parts: [{ partId: '1', filename: 'a.pdf', mimeType: 'application/pdf',
                                body: { size: 9, attachmentId: 'X' } }])
      expect(found).to eq([{ part_id: '1', filename: 'a.pdf', mime_type: 'application/pdf',
                             size: 9, attachment_id: 'X' }])
    end

    it 'reads string-keyed parts too' do
      found = collect('parts' => [{ 'partId' => '0.1', 'filename' => 'b.csv',
                                    'body' => { 'attachmentId' => 'Y' } }])
      expect(found.map { |a| a[:part_id] }).to eq(['0.1'])
    end

    it 'keeps document order across nesting levels' do
      found = collect(parts: [
        { partId: '0', parts: [{ partId: '0.0', filename: 'first', body: { attachmentId: 'A' } }] },
        { partId: '1', filename: 'second', body: { attachmentId: 'B' } }
      ])
      expect(found.map { |a| a[:filename] }).to eq(%w[first second])
    end

    it 'skips a part with a filename but no attachmentId' do
      expect(collect(parts: [{ partId: '1', filename: 'tiny.txt', body: { size: 3, data: 'eHl6' } }])).to eq([])
    end
  end

  describe '.download_attachment' do
    it 'base64url-decodes the payload' do
      stub_response(data: Base64.urlsafe_encode64('hello bytes'))
      expect(described_class.download_attachment(message_id: 'm1', attachment_id: 'A1')).to eq('hello bytes')
    end

    it 'decodes bytes that are not valid UTF-8' do
      raw = "\x89PNG\r\n\x1a\n\xFF\xFE".b
      stub_response(data: Base64.urlsafe_encode64(raw))
      expect(described_class.download_attachment(message_id: 'm1', attachment_id: 'A1').b).to eq(raw)
    end

    it 'raises rather than returning an empty file when the API sends no data' do
      stub_response({})
      expect { described_class.download_attachment(message_id: 'm1', attachment_id: 'A1') }
        .to raise_error(/returned no data/)
    end
  end
end
