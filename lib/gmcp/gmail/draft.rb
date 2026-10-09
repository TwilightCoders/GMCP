module GMCP
  module Gmail
    class Draft
      include Him::Model

      collection_path 'drafts'
      primary_key :id

      parse_root_in_json true
      root_element :drafts

      attributes :id, :message

      class << self
        def create_draft(to:, subject:, body:)
          raw = "To: #{to}\r\nSubject: #{subject}\r\nContent-Type: text/plain\r\n\r\n#{body}"
          post_raw('drafts', { message: { raw: Base64.urlsafe_encode64(raw) } })
        end
      end
    end
  end
end
