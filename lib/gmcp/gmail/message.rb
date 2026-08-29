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
