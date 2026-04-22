# GMCP

Google Workspace MCP server (Gmail, Calendar, Drive) for Claude Code.

Built on [`him`](https://github.com/TwilightCoders/him) (REST ORM), the
[official Ruby MCP SDK](https://github.com/modelcontextprotocol/ruby-sdk),
and Google's OAuth2 library (`googleauth`).

## Why

The built-in claude.ai Gmail/Calendar connectors have limited OAuth scopes —
no trash, no labels, no send, no Drive access. GMCP runs as a local stdio MCP
server with full `gmail.modify`, `calendar.events`, and `drive.readonly` scopes.

## Tools

**Gmail (8 tools)**
`gmail_search`, `gmail_get_message`, `gmail_list_labels`, `gmail_trash_message`,
`gmail_archive_message`, `gmail_label_message`, `gmail_send`, `gmail_create_draft`, `gmail_reply`

**Calendar (7 tools)**
`calendar_list_calendars`, `calendar_list_events`, `calendar_get_event`,
`calendar_create_event`, `calendar_update_event`, `calendar_delete_event`, `calendar_rsvp`

**Drive (3 tools)**
`drive_search`, `drive_list_folder`, `drive_read_file`

## Setup

### 1. Google Cloud project

1. Go to <https://console.cloud.google.com/>
2. Create a project (or use an existing one)
3. Enable the Gmail, Google Calendar, and Google Drive APIs
4. Under **APIs & Services → Credentials**, create an OAuth 2.0 Client ID
   - Application type: **Desktop app**
5. Download the JSON file and save it to `~/.config/gmcp/credentials.json`

### 2. Install

```bash
gem install gmcp     # once published — until then, use path install below
```

Or from source:
```bash
git clone https://github.com/TwilightCoders/GMCP ~/.gmcp
cd ~/.gmcp && bundle install
```

### 3. Authorize your account

```bash
bin/gmcp-auth you@example.com
# → prints an authorization URL

# Open the URL in your browser, approve access, copy the code, then:
bin/gmcp-auth you@example.com <paste-code-here>
# → Token stored at ~/.config/gmcp/you@example.com/token.yaml
```

Run this once per Google account. Tokens auto-refresh on subsequent runs.

### 4. Wire up Claude Code

Add to your Claude Code `settings.json` (usually `~/.claude/settings.json`):

```json
{
  "mcpServers": {
    "gmcp": {
      "command": "/path/to/GMCP/bin/gmcp",
      "env": {
        "GMCP_ACCOUNT": "you@example.com"
      }
    }
  }
}
```

For multiple accounts:

```json
{
  "mcpServers": {
    "gmcp-personal": {
      "command": "/path/to/GMCP/bin/gmcp",
      "env": { "GMCP_ACCOUNT": "you@gmail.com" }
    },
    "gmcp-work": {
      "command": "/path/to/GMCP/bin/gmcp",
      "env": { "GMCP_ACCOUNT": "you@company.com" }
    }
  }
}
```

## Development

```bash
bundle install
bundle exec rake spec
```

Ruby 3.4.9+ required.

## License

MIT. See `LICENSE.txt`.
