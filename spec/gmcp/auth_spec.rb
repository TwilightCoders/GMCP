# frozen_string_literal: true

require 'spec_helper'

describe GMCP::Auth do
  describe '.token_path' do
    it 'returns path under ~/.config/gmcp/<account>/' do
      path = described_class.token_path('user@example.com')
      expect(path).to end_with('/user@example.com/token.yaml')
      expect(path).to include('.config/gmcp')
    end

    it 'is unique per account' do
      expect(described_class.token_path('alice@example.com'))
        .not_to eq(described_class.token_path('bob@example.com'))
    end
  end

  describe '.scopes' do
    it 'returns an array of OAuth scope strings' do
      scopes = described_class.scopes
      expect(scopes).to be_an(Array)
      expect(scopes).not_to be_empty
      expect(scopes).to all(start_with('https://'))
    end

    it 'includes the gmail.modify scope' do
      expect(described_class.scopes).to include(
        'https://www.googleapis.com/auth/gmail.modify'
      )
    end

    it 'includes calendar and drive scopes' do
      expect(described_class.scopes).to include(
        'https://www.googleapis.com/auth/calendar.events',
        'https://www.googleapis.com/auth/calendar.calendarlist.readonly',
        'https://www.googleapis.com/auth/drive.readonly'
      )
    end
  end
end
