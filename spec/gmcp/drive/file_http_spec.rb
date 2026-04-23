# frozen_string_literal: true

require 'spec_helper'

describe GMCP::Drive::File do
  let(:test_api) { Him::API.new(url: GMCP::Apis::DRIVE_BASE) }
  let(:empty_collection) { { parsed_data: { data: { files: [] }, errors: {}, metadata: {} }, response: double('r') } }
  let(:empty_response)   { { parsed_data: { data: {}, errors: {}, metadata: {} }, response: double('r') } }

  around do |ex|
    original = described_class.instance_variable_get(:@_her_use_api)
    described_class.use_api(test_api)
    ex.run
  ensure
    described_class.instance_variable_set(:@_her_use_api, original)
  end

  before { allow(test_api).to receive(:request).and_return(empty_response) }

  describe '.search' do
    it 'GETs /files with q, pageSize, orderBy, and fields' do
      allow(test_api).to receive(:request).and_return(empty_collection)
      described_class.search('name contains "report"', max_results: 10)
      expect(test_api).to have_received(:request).with(
        hash_including(
          _method: :get,
          _path: 'files',
          q: 'name contains "report"',
          pageSize: 10
        )
      )
    end

    it 'includes a fields selector in the request' do
      allow(test_api).to receive(:request).and_return(empty_collection)
      described_class.search('type=pdf')
      expect(test_api).to have_received(:request).with(
        hash_including(fields: 'files(id,name,mimeType,size,modifiedTime,webViewLink)')
      )
    end
  end

  describe '.list_folder' do
    it 'GETs /files with a parent-folder q filter' do
      allow(test_api).to receive(:request).and_return(empty_collection)
      described_class.list_folder('folder123')
      expect(test_api).to have_received(:request) do |params|
        expect(params[:_method]).to eq(:get)
        expect(params[:_path]).to eq('files')
        expect(params[:q]).to include("'folder123' in parents")
        expect(params[:q]).to include('trashed=false')
      end
    end
  end

  describe '.download' do
    it 'GETs /files/:id with alt=media' do
      described_class.download('file123')
      expect(test_api).to have_received(:request).with(
        hash_including(_method: :get, _path: 'files/file123', alt: 'media')
      )
    end
  end
end
