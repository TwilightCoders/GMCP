module GMCP
  module Gmail
    class Label
      include Him::Model

      collection_path '/labels'
      primary_key :id

      parse_root_in_json true
      root_element :labels

      attributes :id, :name, :messageListVisibility, :labelListVisibility, :type,
                 :messagesTotal, :messagesUnread, :threadsTotal, :threadsUnread
    end
  end
end
