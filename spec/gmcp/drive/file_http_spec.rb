# frozen_string_literal: true

require 'spec_helper'

describe GMCP::Drive::File do
  def text(body, status: 200)
    [status, { 'Content-Type' => 'text/plain' }, body]
  end

  def stub_metadata(id, **fields)
    google.get("/drive/v3/files/#{id}") do |env|
      expect(env.params['fields']).to eq('id,name,mimeType,size')
      json(id: id, **fields)
    end
  end

  describe '.search_page' do
    it 'includes shared drives and surfaces the cursor' do
      google.get('/drive/v3/files') do |env|
        expect(env.params).to include(
          'q'                         => "name contains 'report'",
          'pageSize'                  => '10',
          'pageToken'                 => 'p1',
          'supportsAllDrives'         => 'true',
          'includeItemsFromAllDrives' => 'true'
        )
        expect(env.params['fields']).to start_with('nextPageToken,')
        json(files: [{ id: 'f1', name: 'report.txt', mimeType: 'text/plain' }], nextPageToken: 'p2')
      end

      page = with_google { described_class.search_page("name contains 'report'", max_results: 10, page_token: 'p1') }
      expect(page[:files].map(&:name)).to eq(['report.txt'])
      expect(page[:next_page_token]).to eq('p2')
    end

    it 'reports no cursor on the last page' do
      google.get('/drive/v3/files') { json(files: []) }

      expect(with_google { described_class.search_page('x') }[:next_page_token]).to be_nil
    end
  end

  describe '.list_folder_page' do
    it 'escapes the folder id inside the query literal' do
      google.get('/drive/v3/files') do |env|
        expect(env.params['q']).to eq("'it\\'s\\\\odd' in parents and trashed=false")
        json(files: [])
      end

      with_google { described_class.list_folder_page("it's\\odd") }
      google.verify_stubbed_calls
    end
  end

  describe '.quote' do
    it 'backslash-escapes quotes and backslashes' do
      expect(described_class.quote("a'b\\c")).to eq("'a\\'b\\\\c'")
    end
  end

  describe '.read_text' do
    it 'exports a Google Doc as plain text' do
      stub_metadata('doc1', name: 'Notes', mimeType: 'application/vnd.google-apps.document')
      google.get('/drive/v3/files/doc1/export') do |env|
        expect(env.params['mimeType']).to eq('text/plain')
        text("Hello from Docs\n")
      end

      expect(with_google { described_class.read_text('doc1') }).to eq("Hello from Docs\n")
      google.verify_stubbed_calls
    end

    it 'exports a Sheet as CSV' do
      stub_metadata('s1', name: 'Budget', mimeType: 'application/vnd.google-apps.spreadsheet')
      google.get('/drive/v3/files/s1/export') do |env|
        expect(env.params['mimeType']).to eq('text/csv')
        text("a,b\n1,2\n")
      end

      expect(with_google { described_class.read_text('s1') }).to eq("a,b\n1,2\n")
    end

    it 'refuses Google-native types it cannot export as text' do
      stub_metadata('fo1', name: 'Stuff', mimeType: 'application/vnd.google-apps.folder')

      expect { with_google { described_class.read_text('fo1') } }
        .to raise_error(ArgumentError, /cannot be exported as text/)
    end

    # him's JSON parser raises on a text body; the raw path must skip it.
    it 'returns a plain text file verbatim' do
      stub_metadata('t1', name: 'a.txt', mimeType: 'text/plain', size: '11')
      google.get('/drive/v3/files/t1') do |env|
        expect(env.params['alt']).to eq('media')
        expect(env.request_headers['Authorization']).to eq('Bearer test-token')
        text('hello world')
      end

      expect(with_google { described_class.read_text('t1') }).to eq('hello world')
    end

    it 'returns a JSON file as its source text, not a parsed hash' do
      stub_metadata('j1', name: 'a.json', mimeType: 'application/json', size: '9')
      google.get('/drive/v3/files/j1') { json('{"a": 1}') }

      expect(with_google { described_class.read_text('j1') }).to eq('{"a": 1}')
    end

    it 'refuses a binary file without downloading it' do
      stub_metadata('b1', name: 'photo.png', mimeType: 'image/png', size: '2048')

      expect { with_google { described_class.read_text('b1') } }
        .to raise_error(ArgumentError, 'photo.png is image/png, not text')
    end

    it 'refuses a text file over the size limit without downloading it' do
      stub_metadata('big', name: 'huge.log', mimeType: 'text/plain', size: (described_class::MAX_BYTES + 1).to_s)

      expect { with_google { described_class.read_text('big') } }
        .to raise_error(ArgumentError, /huge\.log is 1048577 bytes/)
    end

    it 'refuses an oversized export' do
      stub_metadata('d2', name: 'Tome', mimeType: 'application/vnd.google-apps.document')
      google.get('/drive/v3/files/d2/export') { text('x' * (described_class::MAX_BYTES + 1)) }

      expect { with_google { described_class.read_text('d2') } }.to raise_error(ArgumentError, /Tome is/)
    end

    it 'surfaces a Google error on the download as ApiError' do
      stub_metadata('gone', name: 'g.txt', mimeType: 'text/plain', size: '1')
      google.get('/drive/v3/files/gone') { json({ error: { message: 'File not found' } }, status: 404) }

      expect { with_google { described_class.read_text('gone') } }
        .to raise_error(GMCP::ApiError, /404: File not found/)
    end
  end
end
