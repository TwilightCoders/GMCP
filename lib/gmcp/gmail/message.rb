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

        def send_message(to:, subject:, body:)
          raw = "To: #{to}\r\nSubject: #{subject}\r\nContent-Type: text/plain\r\n\r\n#{body}"
          post_raw('messages/send', { raw: Base64.urlsafe_encode64(raw) })
        end
      end
    end
  end
end
