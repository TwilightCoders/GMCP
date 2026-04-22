require_relative 'lib/gmcp/version'

Gem::Specification.new do |spec|
  spec.name          = 'gmcp'
  spec.version       = GMCP::VERSION
  spec.authors       = ['Dale Stevens']
  spec.email         = ['dale@twilightcoders.net']

  spec.summary       = 'Google Workspace MCP server (Gmail, Calendar, Drive) for Claude Code'
  spec.description   = 'A Ruby MCP server providing full-access Google Workspace tools — Gmail (read, label, trash, send), Calendar (read/write events), and Drive (read). Built on the him REST ORM and the official mcp Ruby SDK.'
  spec.homepage      = 'https://github.com/TwilightCoders/GMCP'
  spec.license       = 'MIT'

  spec.metadata = {
    'allowed_push_host' => 'https://rubygems.org',
    'homepage_uri'      => spec.homepage,
    'source_code_uri'   => spec.homepage,
    'changelog_uri'     => "#{spec.homepage}/blob/main/CHANGELOG.md",
    'bug_tracker_uri'   => "#{spec.homepage}/issues"
  }

  spec.files         = Dir['CHANGELOG.md', 'README.md', 'LICENSE.txt', 'lib/**/*', 'bin/*', 'config/**/*']
  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.1'

  spec.add_dependency 'mcp', '~> 0.13'
  spec.add_dependency 'him', '~> 0.1'
  spec.add_dependency 'googleauth', '~> 1.0'
  spec.add_dependency 'faraday', '~> 2.0'

  spec.add_development_dependency 'bundler', '>= 1.3'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'pry-byebug', '~> 3'
end
