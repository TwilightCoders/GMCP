module GMCP
  module Gmail
    class Message
      include Him::Model

      collection_path 'messages'
      primary_key :id

      parse_root_in_json true
      root_element :messages

      attributes :id, :threadId, :labelIds, :snippet, :payload,
                 :sizeEstimate, :historyId, :internalDate

      # Gmail caps batchModify at 1000 ids per call.
      BATCH_LIMIT = 1000

      # Gmail hands back headers as a flat array of {name:, value:} pairs and
      # the body as base64url leaves of a MIME tree. A caller that receives
      # either raw has to do this decoding itself, which is exactly what
      # happened before these existed.
      #
      # Keys arrive as symbols through `him`, but hand-built and fixture
      # payloads use strings, so every reader below tolerates both.

      SUMMARY_HEADERS = %w[From To Cc Bcc Reply-To Date Subject].freeze

      # Every header on the message, keyed by the name Gmail reported.
      def headers
        @headers ||= (payload_fetch(:headers) || []).each_with_object({}) do |entry, acc|
          next unless entry.is_a?(Hash)

          name = entry[:name] || entry['name']
          acc[name.to_s] = (entry[:value] || entry['value']).to_s if name
        end
      end

      # Senders disagree about header casing — the same header arrives as
      # Message-ID, Message-Id and message-id depending on who sent it — so an
      # exact-match lookup silently misses.
      def header(name)
        key = headers.keys.find { |candidate| candidate.casecmp?(name.to_s) }
        key && headers[key]
      end

      # The message body as readable text. Prefers text/plain; falls back to
      # text/html with markup stripped, because a great deal of mail (most
      # marketing mail) ships no plain part at all, and returning nil for it
      # would make this useless for the mail it is most often pointed at.
      def body_text
        part_text('text/plain') || strip_html(part_text('text/html'))
      end

      # What a caller actually wants from "get me this message": the ids needed
      # for follow-up calls, the headers worth reading, and a decoded body —
      # not the raw MIME tree.
      def to_summary
        summary = {
          id:        id,
          thread_id: threadId,
          label_ids: labelIds,
          snippet:   snippet
        }
        SUMMARY_HEADERS.each do |name|
          value = header(name)
          summary[name.downcase.tr('-', '_').to_sym] = value if value
        end
        summary[:body]    = body_text
        summary[:headers] = headers
        summary
      end

      def trash!
        self.class.post_raw("messages/#{id}/trash", {})
      end

      def untrash!
        self.class.post_raw("messages/#{id}/untrash", {})
      end

      def archive!
        modify!(removeLabelIds: ['INBOX'])
      end

      def modify!(addLabelIds: [], removeLabelIds: [])
        self.class.post_raw("messages/#{id}/modify", {
          addLabelIds:    addLabelIds,
          removeLabelIds: removeLabelIds
        })
      end

      def reply!(body:)
        headers = payload&.dig('headers') || []
        subject   = headers.find { |h| h['name'] == 'Subject' }&.fetch('value', '') || ''
        reply_sub = subject.start_with?('Re:') ? subject : "Re: #{subject}"
        from      = headers.find { |h| h['name'] == 'From' }&.fetch('value', '') || ''
        raw = "To: #{from}\r\nSubject: #{reply_sub}\r\n" \
              "In-Reply-To: #{id}\r\nReferences: #{id}\r\n" \
              "Content-Type: text/plain\r\n\r\n#{body}"
        self.class.post_raw('messages/send', {
          raw:      Base64.urlsafe_encode64(raw),
          threadId: threadId
        })
      end


      private

      def payload_fetch(key)
        hash = payload
        return nil unless hash.is_a?(Hash)

        hash[key] || hash[key.to_s]
      end

      # Depth-first search for the first non-blank part of `mime_type`.
      def part_text(mime_type, part = payload)
        return nil unless part.is_a?(Hash)

        mime = part[:mimeType] || part['mimeType']
        if mime == mime_type
          body = part[:body] || part['body'] || {}
          decoded = decode_part(body[:data] || body['data'], part)
          return decoded if decoded
        end

        (part[:parts] || part['parts'] || []).each do |sub|
          found = part_text(mime_type, sub)
          return found if found
        end
        nil
      end

      # A part carrying undecodable bytes should not take the whole tool call
      # down, and a blank part should not mask a populated one of another type.
      def decode_part(data, part = nil)
        return nil if data.nil? || data.to_s.empty?

        text = to_utf8(Base64.urlsafe_decode64(data), charset_of(part))
        text.strip.empty? ? nil : text
      rescue ArgumentError
        nil
      end

      # The part's own Content-Type carries the charset. Without it a
      # Windows-1252 or Latin-1 body — still common in bulk mail — decodes to
      # mojibake.
      def charset_of(part)
        return nil unless part.is_a?(Hash)

        entries = part[:headers] || part['headers'] || []
        entry = entries.find do |h|
          h.is_a?(Hash) && (h[:name] || h['name']).to_s.casecmp?('Content-Type')
        end
        value = entry && (entry[:value] || entry['value'])
        value.to_s[/charset=["']?([\w.:-]+)/i, 1]
      end

      # Base64.urlsafe_decode64 hands back ASCII-8BIT whatever the bytes are.
      # Left that way, JSON.generate warns on json 2.x and raises on 3.0.
      def to_utf8(text, charset)
        source = Encoding.find(charset || 'UTF-8')
        text = text.dup.force_encoding(source)

        # encode is a no-op when source == destination, so it will not scrub
        # invalid bytes out of a part that merely claims to be UTF-8.
        if source == Encoding::UTF_8
          text.valid_encoding? ? text : text.scrub('')
        else
          text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        end
      rescue ArgumentError, Encoding::ConverterNotFoundError
        text.dup.force_encoding(Encoding::UTF_8).scrub('')
      end

      HTML_ENTITIES = {
        '&nbsp;' => ' ', '&lt;' => '<', '&gt;' => '>',
        '&quot;' => '"', '&#39;' => "'", '&apos;' => "'"
      }.freeze

      # Enough to make an html-only message readable. Not a parser, and not
      # trying to be — the alternative on offer is handing back raw markup.
      def strip_html(html)
        return nil if html.nil?

        text = html.dup
        text.gsub!(%r{<(script|style)\b[^>]*>.*?</\1>}mi, ' ')
        text.gsub!(%r{<br\s*/?>}i, "\n")
        text.gsub!(%r{</(p|div|tr|li|h[1-6]|blockquote|table)>}i, "\n\n")
        text.gsub!(/<[^>]*>/m, '')
        HTML_ENTITIES.each { |entity, char| text.gsub!(entity, char) }
        text.gsub!('&amp;', '&')     # last, so &amp;lt; does not become <
        text.gsub!(/[ \t]+/, ' ')
        text.gsub!(/ *\n */, "\n")
        text.gsub!(/\n{3,}/, "\n\n")
        text.strip!
        text.empty? ? nil : text
      end

      class << self
        def search(query, max_results: 20)
          get_collection('messages', q: query, maxResults: max_results)
        end

        # Like .search, but surfaces Gmail's pagination cursor instead of
        # discarding it. get_collection drops everything outside the message
        # array, which is why callers previously had to drop to raw Faraday to
        # walk a mailbox.
        #
        # Returns { messages:, next_page_token:, estimate: }. next_page_token is
        # nil on the last page — that, not an empty page, is end-of-results.
        # `estimate` is Gmail's resultSizeEstimate and is approximate; never
        # treat it as a count.
        def search_page(query = nil, max_results: 100, page_token: nil, label_ids: nil)
          params = { maxResults: max_results }
          params[:q]         = query      if query && !query.to_s.empty?
          params[:pageToken] = page_token if page_token && !page_token.to_s.empty?
          params[:labelIds]  = label_ids  if label_ids

          get_raw('messages', params) do |parsed, _response|
            data = parsed[:data] || {}
            {
              messages:        (data[:messages] || []).map { |m| new(m) },
              next_page_token: data[:nextPageToken],
              estimate:        data[:resultSizeEstimate]
            }
          end
        end

        # Walks every page of a query, yielding each page. Bounded by max_pages
        # so a caller cannot accidentally spin forever on a mailbox that keeps
        # handing back cursors.
        def each_page(query = nil, max_results: 100, max_pages: 100)
          return enum_for(:each_page, query, max_results: max_results, max_pages: max_pages) unless block_given?

          token = nil
          max_pages.times do
            page = search_page(query, max_results: max_results, page_token: token)
            yield page
            token = page[:next_page_token]
            break if token.nil? || token.to_s.empty?
          end
        end

        # One request for up to BATCH_LIMIT messages. Returns an empty body on
        # success — Gmail reports nothing per-message, so a partial failure is
        # not distinguishable here. Callers wanting per-message confirmation
        # must re-read.
        def batch_modify(ids:, add_label_ids: [], remove_label_ids: [])
          ids = Array(ids)
          raise ArgumentError, 'no message ids given' if ids.empty?
          raise ArgumentError, "batch of #{ids.length} exceeds Gmail's limit of #{BATCH_LIMIT}" if ids.length > BATCH_LIMIT

          post_raw('messages/batchModify', {
            ids:             ids,
            addLabelIds:     add_label_ids,
            removeLabelIds:  remove_label_ids
          })
        end

        # Adding the TRASH label is how the batch endpoint expresses a trash;
        # there is no messages/batchTrash. Recoverable for 30 days, same as a
        # single-message trash.
        def batch_trash(ids:)
          batch_modify(ids: ids, add_label_ids: ['TRASH'])
        end

        def batch_untrash(ids:)
          batch_modify(ids: ids, remove_label_ids: ['TRASH'])
        end

        # Archiving in Gmail is removing INBOX, nothing more.
        def batch_archive(ids:)
          batch_modify(ids: ids, remove_label_ids: ['INBOX'])
        end

        # Attachment parts carry a filename and a body.attachmentId; inline
        # parts (and the text/plain + text/html bodies) carry neither, so this
        # returns only things a user would recognise as an attachment.
        def attachments(message_id)
          payload = get_raw("messages/#{message_id}", format: 'full') { |p, _r| (p[:data] || {})[:payload] } || {}
          collect_attachment_parts(payload)
        end

        # Returns the raw decoded bytes. Callers decide where they land — the
        # model does not write to disk.
        def download_attachment(message_id:, attachment_id:)
          get_raw("messages/#{message_id}/attachments/#{attachment_id}") do |parsed, _response|
            encoded = (parsed[:data] || {})[:data]
            raise "attachment #{attachment_id} returned no data" if encoded.nil?

            Base64.urlsafe_decode64(encoded)
          end
        end

        def send_message(to:, subject:, body:)
          raw = "To: #{to}\r\nSubject: #{subject}\r\nContent-Type: text/plain\r\n\r\n#{body}"
          post_raw('messages/send', { raw: Base64.urlsafe_encode64(raw) })
        end

        private

        def collect_attachment_parts(part, acc = [])
          body = part[:body] || part['body'] || {}
          filename = part[:filename] || part['filename']
          att_id   = body[:attachmentId] || body['attachmentId']

          if att_id && filename && !filename.to_s.empty?
            acc << {
              filename:      filename,
              mime_type:     part[:mimeType] || part['mimeType'],
              size:          body[:size] || body['size'],
              attachment_id: att_id
            }
          end

          (part[:parts] || part['parts'] || []).each { |p| collect_attachment_parts(p, acc) }
          acc
        end
      end
    end
  end
end
