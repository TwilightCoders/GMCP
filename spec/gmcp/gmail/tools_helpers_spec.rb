# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

describe GMCP::Gmail::Tools do
  def text_of(response)
    response.instance_variable_get(:@content).first[:text]
  rescue StandardError
    response.to_h.to_s
  end

  describe '.batching' do
    it 'passes a cleaned id set to the block' do
      seen = nil
      described_class.batching([' a ', 'b', '', nil, 'b']) { |ids| seen = ids; 'ok' }
      expect(seen).to eq(%w[a b])
    end

    it 'refuses an empty set without calling the block' do
      called = false
      r = described_class.batching([]) { called = true }
      expect(called).to be(false)
      expect(r.error?).to be(true)
      expect(text_of(r)).to match(/No message ids/)
    end

    it 'treats a set of only blanks as empty' do
      called = false
      described_class.batching(['', '  ', nil]) { called = true }
      expect(called).to be(false)
    end

    it 'leaves failures to ToolHelpers.guarded' do
      expect { described_class.batching(%w[a]) { raise ArgumentError, 'exceeds the limit' } }
        .to raise_error(ArgumentError)
    end
  end

  describe '.download_attachment_to' do
    around { |ex| Dir.mktmpdir { |d| @dir = d; ex.run } }

    def download(**kw)
      described_class.download_attachment_to(
        **{ message_id: 'm1', attachment_id: 'A1', dest_dir: @dir }.merge(kw)
      )
    end

    it 'writes the bytes and reports the path' do
      allow(GMCP::Gmail::Message).to receive(:download_attachment).and_return('PDFBYTES')
      r = download(filename: 'statement.pdf')
      path = File.join(@dir, 'statement.pdf')
      expect(File.binread(path)).to eq('PDFBYTES')
      expect(text_of(r)).to include('8 bytes', path)
    end

    it 'writes binary content unchanged' do
      raw = "\x89PNG\r\n\x1a\n\xFF\xFE".b
      allow(GMCP::Gmail::Message).to receive(:download_attachment).and_return(raw)
      download(filename: 'x.png')
      expect(File.binread(File.join(@dir, 'x.png')).b).to eq(raw)
    end

    # Gmail reissues attachmentId on every fetch, so the listing and the
    # download are tied together by partId instead.
    it 'names the file after the attachment found by part_id, and downloads by its current id' do
      google.get('/gmail/v1/users/me/messages/m1') do
        json(payload: { parts: [
          { partId: '0', mimeType: 'text/plain', body: { size: 3 } },
          { partId: '1', filename: 'statement.pdf', mimeType: 'application/pdf',
            body: { size: 5, attachmentId: 'FRESH-ID' } }
        ] })
      end
      google.get('/gmail/v1/users/me/messages/m1/attachments/FRESH-ID') { json(data: Base64.urlsafe_encode64('bytes')) }

      r = with_google { download(attachment_id: nil, part_id: '1') }
      expect(r.error?).to be(false)
      expect(File.binread(File.join(@dir, 'statement.pdf'))).to eq('bytes')
      google.verify_stubbed_calls
    end

    it 'refuses a part_id the message does not have' do
      allow(GMCP::Gmail::Message).to receive(:attachments).and_return([{ part_id: '1', filename: 'a.pdf' }])
      expect { download(attachment_id: nil, part_id: '9') }.to raise_error(ArgumentError, /no attachment with part_id 9/)
    end

    it 'falls back to a generic name for a bare attachment_id, without refetching the message' do
      expect(GMCP::Gmail::Message).not_to receive(:attachments)
      allow(GMCP::Gmail::Message).to receive(:download_attachment).and_return('x')
      download(attachment_id: 'ANGjdJ8abcdefghijk')
      expect(File.exist?(File.join(@dir, 'm1-ANGjdJ8abcde.bin'))).to be(true)
    end

    it 'needs one of part_id or attachment_id' do
      r = download(attachment_id: nil)
      expect(r.error?).to be(true)
      expect(text_of(r)).to match(/part_id/)
    end

    # ── the part that matters ──────────────────────────────────────────────
    it 'strips directory traversal out of the filename' do
      allow(GMCP::Gmail::Message).to receive(:download_attachment).and_return('x')
      parent = File.expand_path('..', @dir)
      download(filename: '../escaped.txt')
      expect(File.exist?(File.join(parent, 'escaped.txt'))).to be(false)
      expect(File.exist?(File.join(@dir, 'escaped.txt'))).to be(true)
    end

    it 'strips a deep traversal attempt' do
      allow(GMCP::Gmail::Message).to receive(:download_attachment).and_return('x')
      download(filename: '../../../../tmp/gmcp-escape-check.txt')
      expect(File.exist?('/tmp/gmcp-escape-check.txt')).to be(false)
      expect(File.exist?(File.join(@dir, 'gmcp-escape-check.txt'))).to be(true)
    end

    it 'refuses an absolute path in the filename' do
      allow(GMCP::Gmail::Message).to receive(:download_attachment).and_return('x')
      download(filename: '/etc/gmcp-should-not-exist')
      expect(File.exist?('/etc/gmcp-should-not-exist')).to be(false)
      expect(File.exist?(File.join(@dir, 'gmcp-should-not-exist'))).to be(true)
    end

    it 'refuses a filename that reduces to nothing usable' do
      allow(GMCP::Gmail::Message).to receive(:download_attachment).and_return('x')
      expect(text_of(download(filename: '..'))).to match(/unusable filename/)
    end

    it 'never overwrites an existing file' do
      File.write(File.join(@dir, 'keep.txt'), 'ORIGINAL')
      allow(GMCP::Gmail::Message).to receive(:download_attachment).and_return('REPLACEMENT')
      r = download(filename: 'keep.txt')
      expect(text_of(r)).to match(/Refusing to overwrite/)
      expect(File.read(File.join(@dir, 'keep.txt'))).to eq('ORIGINAL')
    end

    it 'refuses a destination that is not a directory, as an error' do
      r = download(dest_dir: File.join(@dir, 'nope'))
      expect(r.error?).to be(true)
      expect(text_of(r)).to match(/Not a directory/)
    end

    it 'does not fetch bytes when the destination is invalid' do
      expect(GMCP::Gmail::Message).not_to receive(:download_attachment)
      download(dest_dir: File.join(@dir, 'nope'))
    end

    # ToolHelpers.guarded turns it into an isError response.
    it 'lets a download failure propagate, writing nothing' do
      allow(GMCP::Gmail::Message).to receive(:download_attachment).and_raise(GMCP::ApiError.new(404, 'gone'))
      expect { download(filename: 'a.txt') }.to raise_error(GMCP::ApiError)
      expect(File.exist?(File.join(@dir, 'a.txt'))).to be(false)
    end
  end
end
