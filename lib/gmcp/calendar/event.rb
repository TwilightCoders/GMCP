require 'erb'

module GMCP
  module Calendar
    class Event
      include Him::Model

      collection_path 'calendars/primary/events'
      primary_key :id

      parse_root_in_json true
      root_element :items

      attributes :id, :summary, :description, :start, :end, :location,
                 :attendees, :status, :organizer, :recurringEventId, :htmlLink

      DATE_ONLY = /\A\d{4}-\d{2}-\d{2}\z/

      # PATCH, not PUT: PUT replaces the whole event and Google rejects one
      # without start and end. The attendee list is sent whole because Google
      # replaces arrays rather than merging them.
      def rsvp!(response, calendar_id: 'primary')
        list = (attendees || []).map { |a| a.to_h.transform_keys(&:to_s) }
        me = list.find { |a| a['self'] }
        raise ArgumentError, "this account is not an attendee of event #{id}, so it cannot RSVP" unless me

        me['responseStatus'] = response.to_s
        self.class.patch_raw(self.class.path('calendars', calendar_id, 'events', id), { attendees: list })
      end

      # The start as Google reports it: dateTime for timed events, date for
      # all-day ones. The raw hash is unreadable in a listing.
      def starts_at
        return nil unless start.is_a?(Hash)

        start[:dateTime] || start['dateTime'] || start[:date] || start['date']
      end

      class << self
        # Calendar ids are email-like and holiday and contact calendars contain
        # '#', which would otherwise end the path and send the request to the
        # wrong resource.
        def path(*segments)
          segments.map { |s| ERB::Util.url_encode(s.to_s) }.join('/')
        end

        # A YYYY-MM-DD value is an all-day event; anything else is a dateTime.
        # Google wants exactly one of date or dateTime.
        def time_field(value, time_zone: nil)
          return { date: value } if value.to_s.match?(DATE_ONLY)

          { dateTime: value, timeZone: time_zone }.compact
        end

        def fetch(event_id, calendar_id: 'primary')
          get_resource(path('calendars', calendar_id, 'events', event_id))
        end

        def list(**options)
          list_page(**options)[:events]
        end

        # Returns { events:, next_page_token: }; next_page_token is nil on the
        # last page. get_collection would drop the cursor.
        def list_page(calendar_id: 'primary', time_min: nil, time_max: nil, max_results: 20, page_token: nil)
          params = { maxResults: max_results, singleEvents: true, orderBy: 'startTime' }
          params[:timeMin]   = time_min   if time_min
          params[:timeMax]   = time_max   if time_max
          params[:pageToken] = page_token if page_token && !page_token.to_s.empty?

          get_raw(path('calendars', calendar_id, 'events'), params) do |parsed, _response|
            data = parsed[:data] || {}
            {
              events:          (data[:items] || []).map { |e| new(e) },
              next_page_token: data[:nextPageToken]
            }
          end
        end

        # sendUpdates is a query parameter, and him sends non-GET params as the
        # body, so it rides on the path. Without it Google adds attendees
        # silently and nobody is invited.
        def create_event(calendar_id: 'primary', **attrs)
          post_raw(with_updates(path('calendars', calendar_id, 'events'), attrs), attrs)
        end

        def update_event(event_id:, calendar_id: 'primary', **attrs)
          patch_raw(with_updates(path('calendars', calendar_id, 'events', event_id), attrs), attrs)
        end

        def delete_event(event_id:, calendar_id: 'primary')
          delete_raw(path('calendars', calendar_id, 'events', event_id), {})
        end

        private

        def with_updates(base, attrs)
          attendees = attrs[:attendees]
          attendees.nil? || attendees.empty? ? base : "#{base}?sendUpdates=all"
        end
      end
    end
  end
end
