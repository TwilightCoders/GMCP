module GMCP
  module Gmail
    class Draft
      include Him::Model

      collection_path '/drafts'
      primary_key :id

      attributes :id, :message

      custom_post :send

      class << self
        def create_draft(to:, subject:, body:)
          raw = "To: #{to}\r\nSubject: #{subject}\r\nContent-Type: text/plain\r\n\r\n#{body}"
          post_raw('/drafts', { message: { raw: Base64.urlsafe_encode64(raw) } })
        end
      end
    end
  end
end
