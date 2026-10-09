require_relative 'lib/gmcp/version'

Gem::Specification.new do |spec|
  spec.name          = 'gmcp'
  spec.version       = GMCP::VERSION
  spec.authors       = ['TwilightCoders']

  spec.summary       = 'Local MCP server for Gmail, Google Calendar, Drive and Voice'
  spec.description   = 'A local stdio MCP server that gives AI assistants scoped access to Gmail, Google Calendar, Google Drive and Google Voice across several Google accounts, with per-capability grants.'
  spec.homepage      = 'https://github.com/TwilightCoders/GMCP'
  spec.license       = 'MIT'

  spec.metadata = {
    'allowed_push_host' => 'https://rubygems.org',
    'homepage_uri'      => spec.homepage,
    'source_code_uri'   => spec.homepage,
    'changelog_uri'     => "#{spec.homepage}/blob/main/CHANGELOG.md",
    'bug_tracker_uri'   => "#{spec.homepage}/issues",
    'rubygems_mfa_required' => 'true'
  }

  spec.executables   = %w[gmcp gmcp-auth gmail_survey]
  spec.files         = Dir['CHANGELOG.md', 'README.md', 'LICENSE.txt', 'lib/**/*', 'config/**/*'] +
                       spec.executables.map { |exe| "bin/#{exe}" }
  spec.bindir        = 'bin'
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.1'

  spec.add_dependency 'mcp',        '~> 0.13'
  spec.add_dependency 'him',        '~> 0.1'
  spec.add_dependency 'googleauth', '~> 1.16'
  spec.add_dependency 'faraday',    '~> 2.0'
  spec.add_dependency 'base64'
  spec.add_dependency 'webrick', '~> 1.8'

  spec.add_development_dependency 'bundler', '>= 1.3'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'pry-byebug', '~> 3'
end
