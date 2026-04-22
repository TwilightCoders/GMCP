module GMCP
  module Gmail
    class Label
      include Him::Model

      collection_path '/labels'
      primary_key :id

      attributes :id, :name, :messageListVisibility, :labelListVisibility, :type,
                 :messagesTotal, :messagesUnread, :threadsTotal, :threadsUnread
    end
  end
end
