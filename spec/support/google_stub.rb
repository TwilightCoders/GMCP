# frozen_string_literal: true

# Runs models through the real Apis stack (params encoding, JSON, bearer,
# ApiError) against Faraday's :test adapter, rather than stubbing
# Him::API#request and skipping everything that has gone wrong in practice.
#
#   it 'trashes' do
#     google.post('/gmail/v1/users/me/messages/m1/trash') { [200, {}, '{}'] }
#     with_google { GMCP::Gmail::Message.new(id: 'm1').trash! }
#   end
module GoogleStub
  JSON_HEADERS = { 'Content-Type' => 'application/json' }.freeze

  def google
    @google ||= Faraday::Adapter::Test::Stubs.new
  end

  def with_google(&block)
    GMCP::ApiBinding.install!
    GMCP::ApiBinding.with(GMCP::Apis.build(token: 'test-token', adapter: [:test, google]), &block)
  end

  # json(id: 'm1'), json('{"raw":1}'), json({ error: {...} }, status: 404)
  def json(body = nil, status: 200, **fields)
    body ||= fields
    [status, JSON_HEADERS, body.is_a?(String) ? body : JSON.generate(body)]
  end
end

RSpec.configure { |config| config.include GoogleStub }
