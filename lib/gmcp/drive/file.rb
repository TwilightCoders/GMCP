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

      # Large enough for any document worth reading into a conversation, small
      # enough not to flood one.
      MAX_BYTES = 1_048_576

      # Google-native files have no bytes of their own; they must be exported.
      EXPORTS = {
        'application/vnd.google-apps.document'     => 'text/plain',
        'application/vnd.google-apps.spreadsheet'  => 'text/csv',
        'application/vnd.google-apps.presentation' => 'text/plain'
      }.freeze

      GOOGLE_APPS = 'application/vnd.google-apps.'

      TEXT_TYPES = %w[
        application/json application/xml application/javascript application/x-javascript
        application/yaml application/x-yaml application/sql application/x-sh
        application/csv application/x-httpd-php application/toml
      ].freeze

      LIST_FIELDS = 'nextPageToken,files(id,name,mimeType,size,modifiedTime,webViewLink)'

      class << self
        def search(query, **options)
          search_page(query, **options)[:files]
        end

        # Returns { files:, next_page_token: }; next_page_token is nil on the
        # last page. get_collection would drop the cursor, and `fields` must
        # name nextPageToken or Google leaves it out.
        #
        # Without the all-drives flags, files on shared drives are invisible.
        def search_page(query, max_results: 20, order_by: 'modifiedTime desc', page_token: nil)
          params = {
            q: query, pageSize: max_results, orderBy: order_by, fields: LIST_FIELDS,
            supportsAllDrives: true, includeItemsFromAllDrives: true
          }
          params[:pageToken] = page_token if page_token && !page_token.to_s.empty?

          get_raw('files', params) do |parsed, _response|
            data = parsed[:data] || {}
            {
              files:           (data[:files] || []).map { |f| new(f) },
              next_page_token: data[:nextPageToken]
            }
          end
        end

        def list_folder(folder_id, **options)
          search("#{quote(folder_id)} in parents and trashed=false", **options)
        end

        def list_folder_page(folder_id, **options)
          search_page("#{quote(folder_id)} in parents and trashed=false", **options)
        end

        # A value as a Drive query string literal. An unescaped quote in an id
        # would end the literal and let the rest rewrite the query.
        def quote(value)
          "'#{value.to_s.gsub(/[\\']/) { |c| "\\#{c}" }}'"
        end

        # The file's content as text: Google-native files exported, text files
        # downloaded. Raises ArgumentError for anything that is not text or is
        # too large, since there is no useful way to hand either to a model.
        def read_text(file_id)
          meta = metadata(file_id)
          mime = meta[:mimeType].to_s
          name = meta[:name] || file_id

          body =
            if mime.start_with?(GOOGLE_APPS)
              export = EXPORTS[mime]
              raise ArgumentError, "#{name} is a #{mime}, which cannot be exported as text" unless export

              raw_get(Apis.path('files', file_id, 'export'), mimeType: export)
            else
              raise ArgumentError, "#{name} is #{mime.empty? ? 'of unknown type' : mime}, not text" unless text?(mime)
              raise ArgumentError, too_large(name, meta[:size].to_i) if meta[:size].to_i > MAX_BYTES

              raw_get(Apis.path('files', file_id), alt: 'media', supportsAllDrives: true)
            end

          # Exports report no size up front.
          raise ArgumentError, too_large(name, body.bytesize) if body.bytesize > MAX_BYTES

          to_utf8(body)
        end

        def metadata(file_id)
          get_raw(Apis.path('files', file_id), fields: 'id,name,mimeType,size', supportsAllDrives: true) do |parsed, _response|
            parsed[:data] || {}
          end
        end

        def text?(mime)
          mime.start_with?('text/') || TEXT_TYPES.include?(mime) || mime.end_with?('+json', '+xml')
        end

        private

        def too_large(name, bytes)
          "#{name} is #{bytes} bytes; drive_read_file reads at most #{MAX_BYTES}"
        end

        # GET through the bound API's own middleware (bearer token, ApiError,
        # adapter) minus him's JSON parser, which raises on a text body and
        # turns a JSON file into a parsed hash. Built from the stack rather than
        # a fresh Faraday connection so token refresh and error handling stay
        # in one place.
        def raw_get(request_path, params = {})
          connection = her_api.connection
          builder    = connection.builder
          app = builder.handlers
                       .reject { |handler| handler.klass <= Him::Middleware::ParseJSON }
                       .reverse
                       .inject(builder.adapter.build) { |inner, handler| handler.build(inner) }
          request = connection.build_request(:get) { |req| req.url(request_path, params) }
          app.call(builder.build_env(connection, request)).body.to_s
        end

        # Drive does not report a charset for most text files; UTF-8 is the
        # overwhelming case, and invalid bytes are dropped rather than failing
        # the whole read.
        def to_utf8(body)
          text = body.dup.force_encoding(Encoding::UTF_8)
          text.valid_encoding? ? text : text.scrub('')
        end
      end
    end
  end
end
