module GMCP
  module Gmail
    class Message
      include Him::Model

      collection_path '/messages'
      primary_key :id

      attributes :id, :threadId, :labelIds, :snippet, :payload, :sizeEstimate, :historyId, :internalDate

      custom_post :trash, :untrash

      def archive!
        modify!(removeLabelIds: ['INBOX'])
      end

      def label!(add: [], remove: [])
        modify!(addLabelIds: Array(add), removeLabelIds: Array(remove))
      end

      def modify!(add_label_ids: [], remove_label_ids: [], addLabelIds: nil, removeLabelIds: nil)
        self.class.post_raw("/messages/#{id}/modify", {
          addLabelIds:    addLabelIds    || add_label_ids,
          removeLabelIds: removeLabelIds || remove_label_ids
        })
      end

      def reply!(body:, subject: nil)
        self.class.post_raw('/messages/send', draft_payload(body: body, subject: subject, thread_id: threadId, reply_to_id: id))
      end

      class << self
        def search(query, max_results: 20)
          get_collection('/messages', q: query, maxResults: max_results)
        end

        def send_message(to:, subject:, body:)
          post_raw('/messages/send', mime_payload(to: to, subject: subject, body: body))
        end

        private

        def mime_payload(to:, subject:, body:)
          raw = "To: #{to}\r\nSubject: #{subject}\r\nContent-Type: text/plain\r\n\r\n#{body}"
          { raw: Base64.urlsafe_encode64(raw) }
        end
      end
    end
  end
end
