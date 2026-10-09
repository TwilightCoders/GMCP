require 'mcp'
require 'time'

module GMCP
  module Calendar
    module Tools
      def self.register(server)
        ToolHelpers.account_tool(
          server,
          name: 'calendar_list_calendars',
          capability: 'calendar.read',
          description: 'List all calendars on the account',
          properties: {}
        ) do
          ToolHelpers.list_response(Calendar.all, empty_message: 'No calendars found.') do |c|
            "#{c.id}: #{c.summary}#{c.primary ? ' [primary]' : ''}"
          end
        end

        ToolHelpers.account_tool(
          server,
          name: 'calendar_list_events',
          capability: 'calendar.read',
          description: 'List events from a calendar within an optional time range. ' \
                       'Returns a page_token when more results exist; pass it back to get the next page.',
          properties: {
            calendar_id: { type: 'string', description: 'Calendar ID (default: primary)' },
            time_min:    { type: 'string', description: 'RFC3339 start of range (default: now), e.g. 2025-01-01T00:00:00Z' },
            time_max:    { type: 'string', description: 'RFC3339 end of range' },
            max_results: { type: 'integer' },
            page_token:  { type: 'string', description: 'Cursor from a previous call. Omit for the first page.' }
          }
        ) do |calendar_id: 'primary', time_min: nil, time_max: nil, max_results: 20, page_token: nil|
          # Without a lower bound Google starts at the calendar's first event,
          # which can be decades back; "list events" means upcoming ones.
          time_min ||= Time.now.utc.iso8601
          page = Event.list_page(calendar_id: calendar_id, time_min: time_min, time_max: time_max,
                                 max_results: max_results, page_token: page_token)
          lines = page[:events].map { |e| "#{e.id}: #{e.summary} (#{e.starts_at})" }
          body  = lines.empty? ? 'No events found.' : lines.join("\n")
          body += "\n\nMore results available. next page_token: #{page[:next_page_token]}" if page[:next_page_token]
          ToolHelpers.text_response(body)
        end

        ToolHelpers.account_tool(
          server,
          name: 'calendar_get_event',
          capability: 'calendar.read',
          description: 'Get a calendar event by ID',
          properties: {
            event_id:    { type: 'string' },
            calendar_id: { type: 'string', description: 'Calendar ID (default: primary)' }
          },
          required: ['event_id']
        ) do |event_id:, calendar_id: 'primary'|
          ToolHelpers.json_response(Event.fetch(event_id, calendar_id: calendar_id))
        end

        ToolHelpers.account_tool(
          server,
          name: 'calendar_create_event',
          capability: 'calendar.write',
          description: 'Create a calendar event. Pass YYYY-MM-DD dates for an all-day event (the end date is ' \
                       'exclusive). Attendees are sent invitations.',
          properties: {
            summary:     { type: 'string' },
            start_time:  { type: 'string', description: 'RFC3339 datetime, e.g. 2025-06-01T10:00:00-07:00, or YYYY-MM-DD for all-day' },
            end_time:    { type: 'string', description: 'RFC3339 datetime, or YYYY-MM-DD (exclusive) for all-day' },
            time_zone:   { type: 'string', description: 'IANA time zone for timed events, e.g. America/Denver' },
            description: { type: 'string' },
            location:    { type: 'string' },
            attendees:   { type: 'array', items: { type: 'string' }, description: 'Email addresses; each is sent an invitation' },
            calendar_id: { type: 'string' }
          },
          required: ['summary', 'start_time', 'end_time']
        ) do |summary:, start_time:, end_time:, time_zone: nil, description: nil, location: nil, attendees: [], calendar_id: 'primary'|
          attrs = {
            summary:   summary,
            start:     Event.time_field(start_time, time_zone: time_zone),
            end:       Event.time_field(end_time, time_zone: time_zone),
            attendees: attendees.map { |e| { email: e } }
          }
          attrs[:description] = description if description
          attrs[:location]    = location    if location
          Event.create_event(calendar_id: calendar_id, **attrs)
          ToolHelpers.text_response("Event '#{summary}' created.")
        end

        ToolHelpers.account_tool(
          server,
          name: 'calendar_update_event',
          capability: 'calendar.write',
          description: 'Update fields on an existing calendar event. Pass YYYY-MM-DD dates to make it all-day ' \
                       '(the end date is exclusive).',
          properties: {
            event_id:    { type: 'string' },
            summary:     { type: 'string' },
            start_time:  { type: 'string', description: 'RFC3339 datetime, or YYYY-MM-DD for all-day' },
            end_time:    { type: 'string', description: 'RFC3339 datetime, or YYYY-MM-DD (exclusive) for all-day' },
            time_zone:   { type: 'string', description: 'IANA time zone for timed events, e.g. America/Denver' },
            description: { type: 'string' },
            location:    { type: 'string' },
            calendar_id: { type: 'string' }
          },
          required: ['event_id']
        ) do |event_id:, calendar_id: 'primary', summary: nil, start_time: nil, end_time: nil, time_zone: nil, description: nil, location: nil|
          attrs = {}
          attrs[:summary]     = summary                                            if summary
          attrs[:start]       = Event.time_field(start_time, time_zone: time_zone) if start_time
          attrs[:end]         = Event.time_field(end_time, time_zone: time_zone)   if end_time
          attrs[:description] = description                                        if description
          attrs[:location]    = location                                           if location
          Event.update_event(event_id: event_id, calendar_id: calendar_id, **attrs)
          ToolHelpers.text_response("Event #{event_id} updated.")
        end

        ToolHelpers.account_tool(
          server,
          name: 'calendar_delete_event',
          capability: 'calendar.delete',
          description: 'Delete a calendar event',
          properties: {
            event_id:    { type: 'string' },
            calendar_id: { type: 'string' }
          },
          required: ['event_id']
        ) do |event_id:, calendar_id: 'primary'|
          Event.delete_event(event_id: event_id, calendar_id: calendar_id)
          ToolHelpers.text_response("Event #{event_id} deleted.")
        end

        ToolHelpers.account_tool(
          server,
          name: 'calendar_rsvp',
          capability: 'calendar.write',
          description: 'RSVP to a calendar event (accepted, declined, tentative). The account must be an attendee.',
          properties: {
            event_id:    { type: 'string' },
            response:    { type: 'string', enum: %w[accepted declined tentative] },
            calendar_id: { type: 'string', description: 'Calendar ID (default: primary)' }
          },
          required: ['event_id', 'response']
        ) do |event_id:, response:, calendar_id: 'primary'|
          Event.fetch(event_id, calendar_id: calendar_id).rsvp!(response, calendar_id: calendar_id)
          ToolHelpers.text_response("RSVP'd #{response} to event #{event_id}.")
        end
      end
    end
  end
end
