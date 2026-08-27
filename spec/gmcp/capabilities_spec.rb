require 'spec_helper'

RSpec.describe GMCP::Capabilities do
  around do |example|
    original = ENV.fetch('GMCP_CAPABILITIES', :unset)
    described_class.reset!
    example.run
  ensure
    if original == :unset
      ENV.delete('GMCP_CAPABILITIES')
    else
      ENV['GMCP_CAPABILITIES'] = original
    end
    described_class.reset!
  end

  def with_env(value)
    if value.nil?
      ENV.delete('GMCP_CAPABILITIES')
    else
      ENV['GMCP_CAPABILITIES'] = value
    end
    described_class.reset!
  end

  describe 'unset vs empty — the fail-open boundary' do
    it 'grants everything when the variable is not set at all' do
      with_env(nil)
      expect(described_class.granted).to match_array(described_class::ALL)
      expect(described_class).to be_unrestricted
    end

    it 'grants NOTHING when the variable is set but empty' do
      with_env('')
      expect(described_class.granted).to eq([])
      expect(described_class).not_to be_unrestricted
    end

    it 'grants nothing for a value that is only separators and whitespace' do
      with_env(' , ,  ')
      expect(described_class.granted).to eq([])
    end

    it 'refuses every capability under the empty grant set' do
      with_env('')
      described_class::ALL.each do |cap|
        expect(described_class.enabled?(cap)).to be(false), "expected #{cap} to be denied"
      end
    end
  end

  describe '.granted' do
    it 'returns exactly the requested capabilities' do
      with_env('gmail.read,gmail.send')
      expect(described_class.granted).to eq(['gmail.read', 'gmail.send'])
    end

    it 'tolerates surrounding whitespace' do
      with_env(' gmail.read , calendar.read ')
      expect(described_class.granted).to eq(['gmail.read', 'calendar.read'])
    end

    it 'drops unknown capabilities rather than trusting them' do
      with_env('gmail.read,gmail.superuser,gmail.*')
      expect(described_class.granted).to eq(['gmail.read'])
    end

    it 'has no wildcard that would grant everything' do
      with_env('*')
      expect(described_class.granted).to eq([])
    end

    it 'memoizes so a mid-process env change cannot widen the grant' do
      with_env('gmail.read')
      expect(described_class.granted).to eq(['gmail.read'])
      ENV['GMCP_CAPABILITIES'] = 'gmail.read,gmail.send'
      expect(described_class.granted).to eq(['gmail.read'])
    end
  end

  describe '.enabled?' do
    it 'is true for a granted capability' do
      with_env('gmail.read')
      expect(described_class.enabled?('gmail.read')).to be(true)
    end

    it 'is false for a capability that was not granted' do
      with_env('gmail.read')
      expect(described_class.enabled?('gmail.send')).to be(false)
    end

    it 'is true for nil, so ungated tools always register' do
      with_env('')
      expect(described_class.enabled?(nil)).to be(true)
    end
  end

  describe 'ALL' do
    it 'separates destructive and outbound verbs from ordinary modification' do
      expect(described_class::ALL).to include('gmail.read', 'gmail.modify', 'gmail.trash', 'gmail.send')
      expect(described_class::ALL).to include('calendar.read', 'calendar.write', 'calendar.delete')
      expect(described_class::ALL).to include('voice.read', 'voice.modify', 'voice.trash')
    end

    it 'contains no wildcard entry' do
      expect(described_class::ALL).not_to include('*')
      expect(described_class::ALL.select { |c| c.include?('*') }).to be_empty
    end
  end
end
