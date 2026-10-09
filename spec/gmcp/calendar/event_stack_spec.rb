# frozen_string_literal: true

require 'spec_helper'

describe GMCP::Calendar::Event do
  def body_of(env)
    JSON.parse(env.body)
  end

  describe '#rsvp!' do
    let(:event) do
      described_class.new(id: 'evt1', attendees: [
        { email: 'me@example.com', self: true, responseStatus: 'needsAction' },
        { email: 'them@example.com', responseStatus: 'accepted' }
      ])
    end

    # PUT replaces the event and Google rejects one without start and end.
    it 'PATCHes only the attendee list, with this account answered' do
      google.patch('/calendar/v3/calendars/primary/events/evt1') do |env|
        attendees = body_of(env)['attendees']
        expect(body_of(env).keys).to eq(['attendees'])
        expect(attendees.find { |a| a['self'] }['responseStatus']).to eq('declined')
        expect(attendees.find { |a| a['email'] == 'them@example.com' }['responseStatus']).to eq('accepted')
        json(id: 'evt1')
      end

      with_google { event.rsvp!('declined') }
      google.verify_stubbed_calls
    end

    it 'targets the given calendar' do
      google.patch('/calendar/v3/calendars/team%40example.com/events/evt1') { json(id: 'evt1') }

      with_google { event.rsvp!('accepted', calendar_id: 'team@example.com') }
      google.verify_stubbed_calls
    end

    it 'refuses, rather than silently doing nothing, when the account is not an attendee' do
      outsider = described_class.new(id: 'evt1', attendees: [{ email: 'them@example.com' }])

      expect { with_google { outsider.rsvp!('accepted') } }
        .to raise_error(ArgumentError, /not an attendee of event evt1/)
    end
  end

  describe '.fetch' do
    # Holiday calendars carry '#', which unescaped ends the path at
    # 'calendars/en.usa' and asks Google for the wrong resource.
    it 'escapes the calendar id' do
      google.get('/calendar/v3/calendars/en.usa%23holiday%40group.v.calendar.google.com/events/e1') do
        json(id: 'e1', summary: 'Labor Day')
      end

      event = with_google { described_class.fetch('e1', calendar_id: 'en.usa#holiday@group.v.calendar.google.com') }
      expect(event.summary).to eq('Labor Day')
      google.verify_stubbed_calls
    end
  end

  describe '.list_page' do
    it 'surfaces the cursor and passes it back' do
      google.get('/calendar/v3/calendars/primary/events') do |env|
        expect(env.params['pageToken']).to eq('p1')
        json(items: [{ id: 'e2', summary: 'Later', start: { date: '2026-10-12' } }], nextPageToken: 'p2')
      end

      page = with_google { described_class.list_page(page_token: 'p1') }
      expect(page[:events].map(&:id)).to eq(['e2'])
      expect(page[:events].first.starts_at).to eq('2026-10-12')
      expect(page[:next_page_token]).to eq('p2')
    end

    it 'reports no cursor on the last page' do
      google.get('/calendar/v3/calendars/primary/events') { json(items: []) }

      expect(with_google { described_class.list_page }[:next_page_token]).to be_nil
    end
  end

  describe '#starts_at' do
    it 'prefers dateTime for a timed event' do
      expect(described_class.new(start: { dateTime: '2026-10-09T10:00:00-06:00' }).starts_at)
        .to eq('2026-10-09T10:00:00-06:00')
    end
  end

  describe '.time_field' do
    it 'treats a bare date as all-day' do
      expect(described_class.time_field('2026-10-09', time_zone: 'America/Denver')).to eq(date: '2026-10-09')
    end

    it 'keeps a dateTime and its time zone' do
      expect(described_class.time_field('2026-10-09T10:00:00', time_zone: 'America/Denver'))
        .to eq(dateTime: '2026-10-09T10:00:00', timeZone: 'America/Denver')
    end
  end

  describe '.create_event' do
    it 'sends an all-day event as date, not dateTime' do
      google.post('/calendar/v3/calendars/primary/events') do |env|
        expect(body_of(env)['start']).to eq('date' => '2026-10-09')
        expect(body_of(env)['end']).to eq('date' => '2026-10-10')
        expect(env.params).not_to have_key('sendUpdates')
        json(id: 'new')
      end

      with_google do
        described_class.create_event(summary: 'Off',
                                     start: described_class.time_field('2026-10-09'),
                                     end:   described_class.time_field('2026-10-10'))
      end
      google.verify_stubbed_calls
    end

    # Without sendUpdates Google adds the attendees but invites nobody.
    it 'asks Google to send invitations when there are attendees' do
      google.post('/calendar/v3/calendars/primary/events') do |env|
        expect(env.params['sendUpdates']).to eq('all')
        expect(body_of(env)['attendees']).to eq([{ 'email' => 'a@example.com' }])
        json(id: 'new')
      end

      with_google { described_class.create_event(summary: 'Sync', attendees: [{ email: 'a@example.com' }]) }
      google.verify_stubbed_calls
    end
  end
end
