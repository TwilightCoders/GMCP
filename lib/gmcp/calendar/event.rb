module GMCP
  module Calendar
    class Event
      include Him::Model

      collection_path '/calendars/primary/events'
      primary_key :id

      parse_root_in_json true
      root_element :items

      attributes :id, :summary, :description, :start, :end, :location,
                 :attendees, :status, :organizer, :recurringEventId, :htmlLink

      def rsvp!(response)
        me = attendees&.find { |a| a['self'] || a[:self] }
        return unless me
        updated = attendees.map do |a|
          (a['self'] || a[:self]) ? a.merge('responseStatus' => response.to_s) : a
        end
        self.class.put_raw("/calendars/primary/events/#{id}", { attendees: updated })
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

        def update_event(event_id:, calendar_id: 'primary', **attrs)
          patch_raw("/calendars/#{calendar_id}/events/#{event_id}", attrs)
        end

        def delete_event(event_id:, calendar_id: 'primary')
          delete_raw("/calendars/#{calendar_id}/events/#{event_id}", {})
        end
      end
    end
  end
end
