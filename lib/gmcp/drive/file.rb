module GMCP
  module Drive
    class File
      include Him::Model

      collection_path 'files'
      primary_key :id

      parse_root_in_json true
      root_element :files

      attributes :id, :name, :mimeType, :description, :parents, :size,
                 :webViewLink, :webContentLink, :createdTime, :modifiedTime

      class << self
        def search(query, max_results: 20, order_by: 'modifiedTime desc')
          get_collection('files', q: query, pageSize: max_results, orderBy: order_by,
                         fields: 'files(id,name,mimeType,size,modifiedTime,webViewLink)')
        end

        def list_folder(folder_id, max_results: 50)
          search("'#{folder_id}' in parents and trashed=false", max_results: max_results)
        end

        def download(file_id)
          get_raw("files/#{file_id}", alt: 'media') do |data, _response|
            data
          end
        end
      end
    end
  end
end
