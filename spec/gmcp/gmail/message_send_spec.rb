# frozen_string_literal: true

require 'spec_helper'

describe GMCP::Gmail::Message do
  # Captures what was POSTed to messages/send as [header block, body, request].
  def capture_send
    sent = nil
    google.post('/gmail/v1/users/me/messages/send') do |env|
      request = JSON.parse(env.body)
      head, body = Base64.urlsafe_decode64(request['raw']).split("\r\n\r\n", 2)
      sent = [head, Base64.decode64(body).force_encoding(Encoding::UTF_8), request]
      json(id: 'sent1')
    end
    yield
    sent
  end

  describe '.send_message' do
    it 'POSTs the message built by Mime' do
      head, body = capture_send do
        with_google { described_class.send_message(to: 'bob@example.com', subject: 'Hi', body: 'Hello') }
      end
      expect(head).to include("To: bob@example.com\r\n", "Subject: Hi\r\n", 'charset=UTF-8')
      expect(body).to eq('Hello')
    end
  end

  describe '.metadata' do
    it 'asks for only the named headers, trimmed by fields' do
      google.get('/gmail/v1/users/me/messages/m1') do |env|
        expect(env.url.query).to include('format=metadata', 'metadataHeaders=From', 'metadataHeaders=Subject', 'fields=')
        json(id: 'm1', threadId: 't1', payload: { headers: [{ name: 'From', value: 'a@x' }] })
      end

      msg = with_google { described_class.metadata('m1', headers: %w[From Subject]) }
      expect(msg.header('From')).to eq('a@x')
      expect(msg.threadId).to eq('t1')
    end
  end

  describe '#reply!' do
    def original(headers)
      described_class.new(id: '18c2f0a1b2c3d4e5', threadId: 'thread456',
                          payload: { headers: headers.map { |name, value| { name: name, value: value } } })
    end

    def reply_to(headers, body: 'Thanks!')
      capture_send { with_google { original(headers).reply!(body: body) } }
    end

    let(:headers) do
      { 'From' => 'Alice <alice@example.com>', 'Subject' => 'Lunch',
        'Message-Id' => '<CAF123@mail.example.com>' }
    end

    it 'sends into the same Gmail thread' do
      _, _, request = reply_to(headers)
      expect(request['threadId']).to eq('thread456')
    end

    it "threads on the original's RFC Message-ID, not Gmail's id" do
      head, = reply_to(headers)
      expect(head).to include("In-Reply-To: <CAF123@mail.example.com>\r\n",
                              "References: <CAF123@mail.example.com>\r\n")
      expect(head).not_to include('18c2f0a1b2c3d4e5')
    end

    it 'extends an existing References chain' do
      head, = reply_to(headers.merge('References' => '<root@x> <mid@x>'))
      expect(head).to include("References: <root@x> <mid@x> <CAF123@mail.example.com>\r\n")
    end

    it 'omits threading headers when the original has no Message-ID' do
      head, = reply_to(headers.except('Message-Id'))
      expect(head).not_to include('In-Reply-To', 'References')
    end

    it 'replies to From' do
      head, = reply_to(headers)
      expect(head).to include("To: Alice <alice@example.com>\r\n")
    end

    it 'prefers Reply-To over From' do
      head, = reply_to(headers.merge('Reply-To' => 'list@example.com'))
      expect(head).to include("To: list@example.com\r\n")
    end

    it 'prefixes the subject with Re:' do
      head, = reply_to(headers)
      expect(head).to include("Subject: Re: Lunch\r\n")
    end

    it 'does not stack a second Re:, whatever its case' do
      head, = reply_to(headers.merge('Subject' => 'RE: Lunch'))
      expect(head).to include("Subject: RE: Lunch\r\n")
    end

    it 'encodes a non-ASCII subject from the original' do
      head, = reply_to(headers.merge('Subject' => 'Déjeuner'))
      expect(head).to match(/^Subject: =\?UTF-8\?B\?/)
    end

    it 'unfolds a folded header from the original rather than refusing it' do
      head, = reply_to(headers.merge('References' => "<root@x>\r\n <mid@x>"))
      expect(head).to include('References: <root@x> <mid@x> <CAF123@mail.example.com>')
    end

    it 'carries the body' do
      _, body = reply_to(headers, body: 'Merci — à bientôt')
      expect(body).to eq('Merci — à bientôt')
    end

    it 'refuses a message with nobody to reply to' do
      expect { original('Subject' => 'x').reply!(body: 'b') }.to raise_error(ArgumentError, /no From or Reply-To/)
    end
  end
end
