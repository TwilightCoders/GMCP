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
          post_raw('drafts', { message: { raw: Mime.build(to: to, subject: subject, body: body) } })
        end
      end
    end
  end
end
