require 'mcp'

module GMCP
  module Calendar
    module Tools
      def self.register(server)
        ToolHelpers.define_tool(
          server,
          name: 'calendar_list_calendars',
          description: 'List all calendars on the account',
          properties: { **ToolHelpers::ACCOUNT_PARAM }
        ) do |account: nil|
          GMCP::Server.with_account(account) do
            ToolHelpers.list_response(Calendar.all, empty_message: 'No calendars found.') do |c|
              "#{c.id}: #{c.summary}#{c.primary ? ' [primary]' : ''}"
            end
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'calendar_list_events',
          description: 'List events from a calendar within an optional time range',
          properties: {
            calendar_id: { type: 'string', description: 'Calendar ID (default: primary)' },
            time_min:    { type: 'string', description: 'RFC3339 start of range, e.g. 2025-01-01T00:00:00Z' },
            time_max:    { type: 'string', description: 'RFC3339 end of range' },
            max_results: { type: 'integer' },
            **ToolHelpers::ACCOUNT_PARAM
          }
        ) do |calendar_id: 'primary', time_min: nil, time_max: nil, max_results: 20, account: nil|
          GMCP::Server.with_account(account) do
            events = Event.list(calendar_id: calendar_id, time_min: time_min, time_max: time_max, max_results: max_results)
            ToolHelpers.list_response(events, empty_message: 'No events found.') { |e| "#{e.id}: #{e.summary} (#{e.start})" }
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'calendar_get_event',
          description: 'Get a calendar event by ID',
          properties: {
            event_id:    { type: 'string' },
            calendar_id: { type: 'string' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['event_id']
        ) do |event_id:, calendar_id: 'primary', account: nil|
          GMCP::Server.with_account(account) do
            ToolHelpers.json_response(Event.find(event_id))
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'calendar_create_event',
          description: 'Create a calendar event',
          properties: {
            summary:     { type: 'string' },
            start_time:  { type: 'string', description: 'RFC3339 datetime, e.g. 2025-06-01T10:00:00-07:00' },
            end_time:    { type: 'string', description: 'RFC3339 datetime' },
            description: { type: 'string' },
            location:    { type: 'string' },
            attendees:   { type: 'array', items: { type: 'string' }, description: 'Email addresses' },
            calendar_id: { type: 'string' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['summary', 'start_time', 'end_time']
        ) do |summary:, start_time:, end_time:, description: nil, location: nil, attendees: [], calendar_id: 'primary', account: nil|
          GMCP::Server.with_account(account) do
            attrs = {
              summary:   summary,
              start:     { dateTime: start_time },
              end:       { dateTime: end_time },
              attendees: attendees.map { |e| { email: e } }
            }
            attrs[:description] = description if description
            attrs[:location]    = location    if location
            Event.create_event(calendar_id: calendar_id, **attrs)
            ToolHelpers.text_response("Event '#{summary}' created.")
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'calendar_update_event',
          description: 'Update fields on an existing calendar event',
          properties: {
            event_id:    { type: 'string' },
            summary:     { type: 'string' },
            start_time:  { type: 'string', description: 'RFC3339 datetime' },
            end_time:    { type: 'string', description: 'RFC3339 datetime' },
            description: { type: 'string' },
            location:    { type: 'string' },
            calendar_id: { type: 'string' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['event_id']
        ) do |event_id:, calendar_id: 'primary', summary: nil, start_time: nil, end_time: nil, description: nil, location: nil, account: nil|
          GMCP::Server.with_account(account) do
            attrs = {}
            attrs[:summary]     = summary                   if summary
            attrs[:start]       = { dateTime: start_time } if start_time
            attrs[:end]         = { dateTime: end_time }   if end_time
            attrs[:description] = description               if description
            attrs[:location]    = location                  if location
            Event.update_event(event_id: event_id, calendar_id: calendar_id, **attrs)
            ToolHelpers.text_response("Event #{event_id} updated.")
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'calendar_delete_event',
          description: 'Delete a calendar event',
          properties: {
            event_id:    { type: 'string' },
            calendar_id: { type: 'string' },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['event_id']
        ) do |event_id:, calendar_id: 'primary', account: nil|
          GMCP::Server.with_account(account) do
            Event.delete_event(event_id: event_id, calendar_id: calendar_id)
            ToolHelpers.text_response("Event #{event_id} deleted.")
          end
        end

        ToolHelpers.define_tool(
          server,
          name: 'calendar_rsvp',
          description: 'RSVP to a calendar event (accepted, declined, tentative)',
          properties: {
            event_id: { type: 'string' },
            response: { type: 'string', enum: %w[accepted declined tentative] },
            **ToolHelpers::ACCOUNT_PARAM
          },
          required: ['event_id', 'response']
        ) do |event_id:, response:, account: nil|
          GMCP::Server.with_account(account) do
            Event.find(event_id).rsvp!(response)
            ToolHelpers.text_response("RSVP'd #{response} to event #{event_id}.")
          end
        end
      end
    end
  end
end
