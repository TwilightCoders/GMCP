module GMCP
  module Calendar
    class Event
      include Him::Model

      collection_path '/calendars/primary/events'
      primary_key :id

      attributes :id, :summary, :description, :start, :end, :location,
                 :attendees, :status, :organizer, :recurringEventId, :htmlLink

      def rsvp!(response)
        me = attendees&.find { |a| a['self'] }
        return unless me
        self.class.put_raw("/calendars/primary/events/#{id}", {
          attendees: attendees.map { |a| a['self'] ? a.merge('responseStatus' => response.to_s) : a }
        })
      end

      class << self
        def list(calendar_id: 'primary', time_min: nil, time_max: nil, max_results: 20)
          params = { maxResults: max_results, singleEvents: true, orderBy: 'startTime' }
          params[:timeMin] = time_min if time_min
          params[:timeMax] = time_max if time_max
          get_collection("/calendars/#{calendar_id}/events", params)
        end

        def create_event(calendar_id: 'primary', **attrs)
          post_raw("/calendars/#{calendar_id}/events", attrs)
        end
      end
    end
  end
end
