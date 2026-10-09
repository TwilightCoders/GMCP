# frozen_string_literal: true

require 'spec_helper'

describe GMCP::Gmail::Message do
  describe 'model configuration' do
    it 'has collection path /messages' do
      expect(described_class.collection_path).to eq('messages')
    end

    it 'has primary key :id' do
      expect(described_class.primary_key).to eq(:id)
    end

    it 'parses root element :messages for collections' do
      expect(described_class.root_element).to eq(:messages)
    end
  end
end
