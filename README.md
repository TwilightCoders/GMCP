# GMCP

Google Workspace MCP server (Gmail, Calendar, Drive) for Claude Code.

Built on [`him`](https://github.com/TwilightCoders/him) (REST ORM), the
official [`mcp`](https://github.com/modelcontextprotocol/ruby-sdk) Ruby SDK,
and Google's OAuth2 (`googleauth`).

## Why

The built-in claude.ai Gmail/Calendar connectors have limited OAuth scopes —
no trash, no label, no send, no Drive access. GMCP runs as a stdio MCP server
with full `gmail.modify`, `calendar.events`, and `drive.readonly` scopes.

## Status

Early development. See `SKETCH.md` for the architectural plan.

## Installation

Not yet published.

```ruby
gem 'gmcp'
```

## Usage

TODO

## Development

```bash
bundle install
bundle exec rspec
```

## License

MIT. See `LICENSE.txt`.
