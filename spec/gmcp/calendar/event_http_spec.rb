# frozen_string_literal: true

require 'spec_helper'

describe GMCP::Calendar::Event do
  let(:test_api) { Him::API.new(url: GMCP::Apis::CALENDAR_BASE) }
  let(:empty_collection) { { parsed_data: { data: { items: [] }, errors: {}, metadata: {} }, response: double('r') } }
  let(:empty_response)   { { parsed_data: { data: {}, errors: {}, metadata: {} }, response: double('r') } }

  around do |ex|
    original = described_class.instance_variable_get(:@_her_use_api)
    described_class.use_api(test_api)
    ex.run
  ensure
    described_class.instance_variable_set(:@_her_use_api, original)
  end

  before { allow(test_api).to receive(:request).and_return(empty_response) }

  describe '.list' do
    it 'GETs /calendars/primary/events with pagination params' do
      allow(test_api).to receive(:request).and_return(empty_collection)
      described_class.list
      expect(test_api).to have_received(:request).with(
        hash_including(
          _method: :get,
          _path: 'calendars/primary/events',
          maxResults: 20,
          singleEvents: true,
          orderBy: 'startTime'
        )
      )
    end

    it 'passes timeMin and timeMax when supplied' do
      allow(test_api).to receive(:request).and_return(empty_collection)
      described_class.list(time_min: '2026-01-01T00:00:00Z', time_max: '2026-12-31T23:59:59Z')
      expect(test_api).to have_received(:request).with(
        hash_including(
          timeMin: '2026-01-01T00:00:00Z',
          timeMax: '2026-12-31T23:59:59Z'
        )
      )
    end

    it 'uses supplied calendar_id in path, escaped' do
      allow(test_api).to receive(:request).and_return(empty_collection)
      described_class.list(calendar_id: 'work@group.calendar.google.com')
      expect(test_api).to have_received(:request).with(
        hash_including(_path: 'calendars/work%40group.calendar.google.com/events')
      )
    end
  end

  describe '.find' do
    it 'GETs /calendars/primary/events/:id' do
      allow(test_api).to receive(:request).and_return(
        { parsed_data: { data: { id: 'evt123' }, errors: {}, metadata: {} }, response: double('r', success?: true) }
      )
      described_class.find('evt123')
      expect(test_api).to have_received(:request).with(
        hash_including(_method: :get, _path: 'calendars/primary/events/evt123')
      )
    end
  end

  describe '.create_event' do
    it 'POSTs /calendars/primary/events with attributes' do
      described_class.create_event(summary: 'Standup', start: { dateTime: '2026-05-01T09:00:00Z' })
      expect(test_api).to have_received(:request).with(
        hash_including(
          _method: :post,
          _path: 'calendars/primary/events',
          summary: 'Standup'
        )
      )
    end
  end

  describe '.update_event' do
    it 'PATCHes /calendars/primary/events/:id with attributes' do
      described_class.update_event(event_id: 'evt123', summary: 'Rescheduled')
      expect(test_api).to have_received(:request).with(
        hash_including(
          _method: :patch,
          _path: 'calendars/primary/events/evt123',
          summary: 'Rescheduled'
        )
      )
    end
  end

  describe '.delete_event' do
    it 'DELETEs /calendars/primary/events/:id' do
      described_class.delete_event(event_id: 'evt123')
      expect(test_api).to have_received(:request).with(
        hash_including(_method: :delete, _path: 'calendars/primary/events/evt123')
      )
    end
  end
end
