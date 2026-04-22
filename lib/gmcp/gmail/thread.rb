module GMCP
  module Gmail
    class Thread
      include Him::Model

      collection_path '/threads'
      primary_key :id

      attributes :id, :snippet, :historyId, :messages

      custom_post :trash, :untrash

      def archive!
        self.class.post_raw("/threads/#{id}/modify", { removeLabelIds: ['INBOX'] })
      end

      class << self
        def search(query, max_results: 20)
          get_collection('/threads', q: query, maxResults: max_results)
        end
      end
    end
  end
end
