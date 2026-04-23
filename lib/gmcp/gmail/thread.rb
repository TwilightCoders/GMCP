module GMCP
  module Gmail
    class Thread
      include Him::Model

      collection_path 'threads'
      primary_key :id

      parse_root_in_json true
      root_element :threads

      attributes :id, :snippet, :historyId, :messages

      def trash!
        self.class.post_raw("/threads/#{id}/trash", {})
      end

      def untrash!
        self.class.post_raw("/threads/#{id}/untrash", {})
      end

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
