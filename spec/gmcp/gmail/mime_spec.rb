# frozen_string_literal: true

require 'spec_helper'

describe GMCP::Gmail::Mime do
  # [header block, decoded body]
  def parse(raw)
    head, body = Base64.urlsafe_decode64(raw).split("\r\n\r\n", 2)
    [head, Base64.decode64(body).force_encoding(Encoding::UTF_8)]
  end

  def build(**overrides)
    described_class.build(**{ to: 'bob@example.com', subject: 'Hi', body: 'Hello' }.merge(overrides))
  end

  it 'declares MIME, a UTF-8 charset and its transfer encoding' do
    head, = parse(build)
    expect(head).to include('MIME-Version: 1.0',
                            'Content-Type: text/plain; charset=UTF-8',
                            'Content-Transfer-Encoding: base64')
  end

  it 'returns base64url, which Gmail requires for raw' do
    raw = build(body: '?' * 300)
    expect(raw).not_to match(%r{[+/]})
  end

  it 'carries the body intact, non-ASCII included' do
    _, body = parse(build(body: "Grüße — 日本語\nsecond line"))
    expect(body).to eq("Grüße — 日本語\r\nsecond line")
  end

  it 'leaves an ASCII subject readable' do
    head, = parse(build(subject: 'Quarterly numbers'))
    expect(head).to include("Subject: Quarterly numbers\r\n")
  end

  it 'RFC 2047 encodes a non-ASCII subject' do
    head, = parse(build(subject: 'Café — résumé'))
    subject = head[/^Subject: (.*?)\r\n(?! )/m, 1]
    expect(subject).to be_ascii_only
    words = subject.scan(/=\?UTF-8\?B\?([^?]*)\?=/).flatten
    expect(words.map { |w| Base64.decode64(w) }.join.force_encoding(Encoding::UTF_8)).to eq('Café — résumé')
  end

  it 'splits a long non-ASCII subject into words within the 75-character limit' do
    head, = parse(build(subject: 'é' * 100))
    words = head.scan(/=\?UTF-8\?B\?[^?]*\?=/)
    expect(words.length).to be > 1
    expect(words.map(&:length).max).to be <= 75
    expect(words.map { |w| Base64.decode64(w[10..-3]) }.join.force_encoding(Encoding::UTF_8)).to eq('é' * 100)
  end

  it 'encodes only the display name of a non-ASCII address' do
    head, = parse(build(to: 'José Núñez <jose@example.com>'))
    expect(head).to match(/^To: =\?UTF-8\?B\?[^?]+\?= <jose@example\.com>\r\n/)
  end

  it 'adds Cc only when given' do
    expect(parse(build).first).not_to include('Cc:')
    expect(parse(build(cc: 'carol@example.com')).first).to include("Cc: carol@example.com\r\n")
  end

  it 'adds extra headers' do
    head, = parse(build(headers: { 'In-Reply-To' => '<a@x>' }))
    expect(head).to include("In-Reply-To: <a@x>\r\n")
  end

  it 'folds a long header at whitespace without changing its value' do
    refs = Array.new(10) { |i| "<message-#{i}@mail.example.com>" }.join(' ')
    head, = parse(build(headers: { 'References' => refs }))
    expect(head.lines.map { |l| l.chomp.length }.max).to be <= 78
    expect(head.gsub("\r\n ", ' ')).to include("References: #{refs}\r\n")
  end

  describe 'header injection' do
    it 'refuses a newline in the subject' do
      expect { build(subject: "Hi\r\nBcc: eve@example.com") }.to raise_error(ArgumentError, /Subject.*line break/)
    end

    it 'refuses a bare LF in a recipient' do
      expect { build(to: "bob@example.com\nBcc: eve@example.com") }.to raise_error(ArgumentError, /To/)
    end

    it 'refuses a bare CR in an extra header' do
      expect { build(headers: { 'References' => "<a@x>\rBcc: eve" }) }.to raise_error(ArgumentError)
    end

    it 'refuses a header name that would smuggle its own field' do
      expect { build(headers: { "X-A: 1\r\nBcc" => 'eve' }) }.to raise_error(ArgumentError, /header name/)
    end

    it 'allows newlines in the body, which is encoded rather than inlined' do
      _, body = parse(build(body: "line\r\nBcc: eve@example.com"))
      expect(body).to eq("line\r\nBcc: eve@example.com")
    end
  end
end
