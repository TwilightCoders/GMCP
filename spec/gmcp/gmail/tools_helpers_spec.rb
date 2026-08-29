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
      expect(text_of(r)).to match(/No message ids/)
    end

    it 'treats a set of only blanks as empty' do
      called = false
      described_class.batching(['', '  ', nil]) { called = true }
      expect(called).to be(false)
    end

    it 'reports a refused batch as readable text, not an exception' do
      r = described_class.batching(%w[a]) { raise ArgumentError, 'exceeds the limit' }
      expect(text_of(r)).to match(/Refused: exceeds the limit/)
    end

    it 'reports an API failure as readable text, not an MCP internal error' do
      r = described_class.batching(%w[a]) { raise 'boom' }
      expect(text_of(r)).to match(/Batch failed: RuntimeError: boom/)
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

    it 'falls back to the attachment’s own filename' do
      allow(GMCP::Gmail::Message).to receive(:attachments)
        .and_return([{ attachment_id: 'A1', filename: 'from-header.csv' }])
      allow(GMCP::Gmail::Message).to receive(:download_attachment).and_return('x')
      download
      expect(File.exist?(File.join(@dir, 'from-header.csv'))).to be(true)
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

    it 'refuses a destination that is not a directory' do
      expect(text_of(download(dest_dir: File.join(@dir, 'nope')))).to match(/Not a directory/)
    end

    it 'does not fetch bytes when the destination is invalid' do
      expect(GMCP::Gmail::Message).not_to receive(:download_attachment)
      download(dest_dir: File.join(@dir, 'nope'))
    end

    it 'reports a download failure as readable text' do
      allow(GMCP::Gmail::Message).to receive(:download_attachment).and_raise('network down')
      expect(text_of(download(filename: 'a.txt'))).to match(/Download failed: RuntimeError: network down/)
    end
  end
end
