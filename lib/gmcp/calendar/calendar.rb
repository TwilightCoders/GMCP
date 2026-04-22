module GMCP
  module Calendar
    class Calendar
      include Him::Model

      collection_path '/users/me/calendarList'
      primary_key :id

      attributes :id, :summary, :description, :timeZone, :primary, :accessRole,
                 :backgroundColor, :foregroundColor
    end
  end
end
