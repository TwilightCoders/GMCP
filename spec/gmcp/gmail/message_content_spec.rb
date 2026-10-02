# frozen_string_literal: true

require 'spec_helper'

# Gmail returns a message body as base64url-encoded leaves of a MIME tree, and
# its headers as a flat array of {name:, value:} pairs. Neither is usable by a
# caller as-is, so a tool that hands either back raw has only moved the decoding
# problem rather than solved it. These are the accessors that do the decoding.
#
# Keys arrive as symbols through `him`, but a payload constructed by hand (or by
# a fixture) uses strings, and the rest of the model already tolerates both — so
# every accessor here is exercised against both.
describe GMCP::Gmail::Message do
  def encode(text)
    Base64.urlsafe_encode64(text)
  end

  describe '#headers' do
    it 'flattens the name/value pairs into a hash' do
      msg = described_class.new(payload: {
        headers: [
          { name: 'From',    value: 'alice@example.com' },
          { name: 'Subject', value: 'Quarterly numbers' }
        ]
      })

      expect(msg.headers).to eq(
        'From' => 'alice@example.com',
        'Subject' => 'Quarterly numbers'
      )
    end

    it 'reads string-keyed payloads too' do
      msg = described_class.new(payload: {
        'headers' => [{ 'name' => 'Subject', 'value' => 'Hello' }]
      })

      expect(msg.headers).to eq('Subject' => 'Hello')
    end

    it 'is empty rather than nil when the payload has no headers' do
      expect(described_class.new(payload: {}).headers).to eq({})
    end

    it 'is empty rather than raising when there is no payload at all' do
      expect(described_class.new(id: 'x').headers).to eq({})
    end
  end

  describe '#header' do
    let(:msg) do
      described_class.new(payload: {
        headers: [{ name: 'Message-ID', value: '<abc@example.com>' }]
      })
    end

    # Senders disagree about casing — the same header arrives as Message-ID,
    # Message-Id and message-id depending on who sent it — so an exact-match
    # lookup silently misses.
    it 'matches case-insensitively' do
      expect(msg.header('message-id')).to eq('<abc@example.com>')
      expect(msg.header('Message-Id')).to eq('<abc@example.com>')
    end

    it 'returns nil for a header that is absent' do
      expect(msg.header('Reply-To')).to be_nil
    end
  end

  describe '#body_text' do
    it 'decodes a single-part text/plain body' do
      msg = described_class.new(payload: {
        mimeType: 'text/plain',
        body: { data: encode("Line one\nLine two") }
      })

      expect(msg.body_text).to eq("Line one\nLine two")
    end

    it 'prefers text/plain over text/html in a multipart/alternative' do
      msg = described_class.new(payload: {
        mimeType: 'multipart/alternative',
        parts: [
          { mimeType: 'text/html',  body: { data: encode('<p>html version</p>') } },
          { mimeType: 'text/plain', body: { data: encode('plain version') } }
        ]
      })

      expect(msg.body_text).to eq('plain version')
    end

    it 'finds a text/plain part nested several levels deep' do
      msg = described_class.new(payload: {
        mimeType: 'multipart/mixed',
        parts: [
          { mimeType: 'application/pdf', filename: 'a.pdf', body: { attachmentId: 'att1' } },
          {
            mimeType: 'multipart/alternative',
            parts: [{ mimeType: 'text/plain', body: { data: encode('buried body') } }]
          }
        ]
      })

      expect(msg.body_text).to eq('buried body')
    end

    # Plenty of senders — most marketing mail — ship html and no plain part at
    # all. Returning nil there would make the tool useless for exactly the mail
    # it is most often pointed at.
    it 'falls back to text/html with tags stripped when there is no plain part' do
      html = '<html><body><p>Hello <b>there</b></p><p>Second line</p></body></html>'
      msg = described_class.new(payload: {
        mimeType: 'text/html',
        body: { data: encode(html) }
      })

      expect(msg.body_text).to eq("Hello there\n\nSecond line")
    end

    it 'drops script and style content rather than rendering it as text' do
      html = '<html><head><style>.a{color:red}</style></head>' \
             '<body><script>alert(1)</script><p>Real text</p></body></html>'
      msg = described_class.new(payload: {
        mimeType: 'text/html',
        body: { data: encode(html) }
      })

      expect(msg.body_text).to eq('Real text')
    end

    it 'unescapes html entities in the stripped fallback' do
      msg = described_class.new(payload: {
        mimeType: 'text/html',
        body: { data: encode('<p>Tom &amp; Jerry &lt;tom@example.com&gt;&nbsp;x</p>') }
      })

      expect(msg.body_text).to eq('Tom & Jerry <tom@example.com> x')
    end

    it 'reads string-keyed parts too' do
      msg = described_class.new(payload: {
        'mimeType' => 'multipart/alternative',
        'parts' => [{ 'mimeType' => 'text/plain', 'body' => { 'data' => encode('string keys') } }]
      })

      expect(msg.body_text).to eq('string keys')
    end

    it 'is nil when no text part exists at all' do
      msg = described_class.new(payload: {
        mimeType: 'multipart/mixed',
        parts: [{ mimeType: 'image/png', filename: 'x.png', body: { attachmentId: 'att1' } }]
      })

      expect(msg.body_text).to be_nil
    end

    it 'is nil rather than raising when there is no payload' do
      expect(described_class.new(id: 'x').body_text).to be_nil
    end

    # Gmail's base64url output is not always padded. urlsafe_decode64 accepts
    # unpadded input, but a part carrying genuinely undecodable bytes should not
    # take the whole tool call down.
    it 'decodes an unpadded base64url part' do
      unpadded = Base64.urlsafe_encode64('abcde').delete('=')
      msg = described_class.new(payload: {
        mimeType: 'text/plain', body: { data: unpadded }
      })

      expect(msg.body_text).to eq('abcde')
    end

    it 'returns nil for an undecodable part instead of raising' do
      msg = described_class.new(payload: {
        mimeType: 'text/plain', body: { data: '!!!not base64!!!' }
      })

      expect { msg.body_text }.not_to raise_error
      expect(msg.body_text).to be_nil
    end
  end

  # Base64.urlsafe_decode64 returns an ASCII-8BIT string whatever the bytes
  # actually are. Handed to JSON.generate that warns on json 2.x and raises on
  # 3.0, and any non-UTF-8 body renders as mojibake — so the part's declared
  # charset has to be honoured at decode time.
  describe '#body_text encoding' do
    def part_with(bytes, charset: nil)
      headers = charset ? [{ name: 'Content-Type', value: "text/plain; charset=#{charset}" }] : []
      described_class.new(payload: {
        mimeType: 'text/plain',
        headers: headers,
        body: { data: Base64.urlsafe_encode64(bytes) }
      })
    end

    it 'tags a decoded body as UTF-8, not BINARY' do
      msg = part_with('plain ascii')

      expect(msg.body_text.encoding).to eq(Encoding::UTF_8)
    end

    it 'keeps multi-byte UTF-8 intact' do
      msg = part_with('café — naïve'.dup.force_encoding(Encoding::BINARY), charset: 'utf-8')

      expect(msg.body_text).to eq('café — naïve')
      expect(msg.body_text.encoding).to eq(Encoding::UTF_8)
    end

    it 'transcodes a declared ISO-8859-1 body into UTF-8' do
      latin1 = 'caf'.dup.force_encoding(Encoding::UTF_8) + 0xE9.chr # café in latin-1
      msg = part_with(latin1.force_encoding(Encoding::BINARY), charset: 'iso-8859-1')

      expect(msg.body_text).to eq('café')
      expect(msg.body_text.encoding).to eq(Encoding::UTF_8)
    end

    it 'survives an unknown charset rather than raising' do
      msg = part_with('hello', charset: 'x-not-a-real-charset')

      expect(msg.body_text).to eq('hello')
      expect(msg.body_text.encoding).to eq(Encoding::UTF_8)
    end

    it 'scrubs invalid bytes rather than raising' do
      msg = part_with("ok\xC3\x28bad".dup.force_encoding(Encoding::BINARY), charset: 'utf-8')

      expect { msg.body_text }.not_to raise_error
      expect(msg.body_text).to include('ok')
      expect(msg.body_text).to be_valid_encoding
    end

    it 'produces a body JSON.generate accepts without an encoding warning' do
      msg = part_with('café'.dup.force_encoding(Encoding::BINARY), charset: 'utf-8')

      warnings = []
      original = Warning.method(:warn)
      Warning.singleton_class.define_method(:warn) { |m, **| warnings << m }
      begin
        GMCP::ToolHelpers.json_response(msg.to_summary)
      ensure
        Warning.singleton_class.define_method(:warn, original)
      end

      expect(warnings.grep(/BINARY/)).to be_empty
    end
  end

  describe '#to_summary' do
    let(:msg) do
      described_class.new(
        id: 'm1', threadId: 't1', labelIds: %w[INBOX UNREAD],
        snippet: 'Quarterly numbers attached',
        internalDate: '1759300000000',
        payload: {
          mimeType: 'text/plain',
          headers: [
            { name: 'From',    value: 'alice@example.com' },
            { name: 'To',      value: 'bob@example.com' },
            { name: 'Date',    value: 'Wed, 1 Oct 2026 09:00:00 -0600' },
            { name: 'Subject', value: 'Quarterly numbers' }
          ],
          body: { data: Base64.urlsafe_encode64('See attached.') }
        }
      )
    end

    it 'carries the identifiers a caller needs for follow-up calls' do
      expect(msg.to_summary).to include(
        id: 'm1', thread_id: 't1', label_ids: %w[INBOX UNREAD]
      )
    end

    it 'surfaces the common headers at the top level' do
      expect(msg.to_summary).to include(
        from: 'alice@example.com',
        to: 'bob@example.com',
        subject: 'Quarterly numbers',
        date: 'Wed, 1 Oct 2026 09:00:00 -0600'
      )
    end

    it 'includes the decoded body rather than the raw payload' do
      summary = msg.to_summary

      expect(summary[:body]).to eq('See attached.')
      expect(summary).not_to have_key(:payload)
    end

    it 'keeps every header available under :headers for the uncommon ones' do
      expect(msg.to_summary[:headers]).to include('From', 'To', 'Date', 'Subject')
    end

    it 'round-trips through JSON without emitting an inspect string' do
      json = GMCP::ToolHelpers.json_response(msg.to_summary).content.first[:text]

      expect(json).not_to include('#<')
      expect(JSON.parse(json)).to include('subject' => 'Quarterly numbers')
    end
  end
end
