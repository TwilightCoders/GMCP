# GMCP — Google Workspace MCP Server

A Ruby MCP server providing full-access Google Workspace tools for Claude Code.
Built on `him` (REST ORM), `mcp` (official Ruby MCP SDK), and optionally `ergane` (CLI).

## Why

The built-in claude.ai Gmail/Calendar connectors have limited OAuth scopes — no trash,
no label, no send, no Drive access. This gives us full control.

## Services

### Gmail
- **Read:** search, read message, read thread, list labels
- **Write:** trash, archive, label, send, draft, reply
- Models: `GMCP::Gmail::Message`, `Thread`, `Label`, `Draft`

### Calendar
- **Read:** list calendars, list events, get event, find free time
- **Write:** create event, update event, delete event, RSVP
- Models: `GMCP::Calendar::Event`, `Calendar`

### Drive
- **Read:** search files, read/download file content, list files in folder
- **Write:** defer for now (upload/create is a rabbit hole)
- Models: `GMCP::Drive::File`, `Folder`

### Deferred
- Sheets (tabular data is its own beast)
- Admin SDK (org-level, not needed)
- Contacts (maybe later)

## Architecture

```
GMCP/
├── gmcp.gemspec
├── Gemfile
├── bin/
│   └── gmcp                    # Entrypoint (stdio MCP server)
├── lib/
│   ├── gmcp.rb                 # Top-level namespace, config
│   ├── gmcp/
│   │   ├── version.rb
│   │   ├── auth.rb             # OAuth2 flow — browser redirect, token persistence
│   │   ├── server.rb           # MCP server setup (tool registration via `mcp` gem)
│   │   ├── gmail/
│   │   │   ├── message.rb      # Him::Model — maps to Gmail Messages API
│   │   │   ├── thread.rb       # Him::Model — maps to Gmail Threads API
│   │   │   ├── label.rb        # Him::Model — maps to Gmail Labels API
│   │   │   ├── draft.rb        # Him::Model — maps to Gmail Drafts API
│   │   │   └── tools.rb        # MCP tool definitions for Gmail
│   │   ├── calendar/
│   │   │   ├── event.rb        # Him::Model
│   │   │   ├── calendar.rb     # Him::Model
│   │   │   └── tools.rb        # MCP tool definitions for Calendar
│   │   └── drive/
│   │       ├── file.rb          # Him::Model
│   │       └── tools.rb         # MCP tool definitions for Drive
│   └── gmcp/
│       └── cli.rb              # Ergane CLI (optional, standalone use)
├── config/
│   └── scopes.yml              # OAuth scope definitions per service
├── spec/
│   └── ...
└── .claude/
    └── CONTEXT.md
```

## Auth

- Google Cloud project with Gmail, Calendar, and Drive APIs enabled
- OAuth2 desktop app credentials (`credentials.json`)
- First run: browser-based consent flow, stores refresh token at `~/.config/gmcp/token.json`
- Subsequent runs: silent refresh
- Scopes:
  - `gmail.modify` (read, label, trash, archive — not full `mail.google.com`)
  - `calendar.events` (read/write events)
  - `drive.readonly` (read files, defer write)

## Dependencies

```ruby
# gmcp.gemspec
spec.add_dependency "mcp", "~> 0.13"
spec.add_dependency "him", "~> 0.1"
spec.add_dependency "googleauth", "~> 1.0"    # Google OAuth2
spec.add_dependency "faraday", "~> 2.0"       # HTTP (Him dependency too)

# Optional
spec.add_dependency "ergane", "~> 0.1"        # CLI layer
```

## MCP Server Config (settings.json)

```json
{
  "mcpServers": {
    "gmcp": {
      "command": "ruby",
      "args": ["/path/to/GMCP/bin/gmcp"],
      "env": {
        "GMCP_ACCOUNT": "personal@example.com"
      }
    }
  }
}
```

Multi-account: `GMCP_ACCOUNT` selects which stored token to use. Could support
both personal and enterprise Gmail from one server.

## Him Model Example

```ruby
module GMCP
  module Gmail
    class Message < Him::Model
      base_url "https://gmail.googleapis.com/gmail/v1/users/me"
      resource_path "/messages"

      attribute :id
      attribute :thread_id
      attribute :label_ids
      attribute :snippet
      attribute :payload

      # Custom actions beyond CRUD
      def trash!
        self.class.connection.post("#{resource_path}/#{id}/trash")
      end

      def archive!
        modify!(remove_label_ids: ["INBOX"])
      end

      def modify!(add_label_ids: [], remove_label_ids: [])
        self.class.connection.post("#{resource_path}/#{id}/modify", {
          addLabelIds: add_label_ids,
          removeLabelIds: remove_label_ids
        })
      end
    end
  end
end
```

## MCP Tool Example

```ruby
# lib/gmcp/gmail/tools.rb
server.tool("gmail_trash_message",
  description: "Move a Gmail message to trash",
  input_schema: {
    type: "object",
    properties: {
      message_id: { type: "string", description: "Gmail message ID" }
    },
    required: ["message_id"]
  }
) do |args|
  message = GMCP::Gmail::Message.find(args["message_id"])
  message.trash!
  "Message #{args["message_id"]} moved to trash"
end
```

## Open Questions

1. **Him readiness** — does 0.1.0 support custom actions (trash!, modify!) or just CRUD?
   Need to check current Him source on the home machine.
2. **Token storage** — `~/.config/gmcp/` or `~/.claude/gmcp/`? Former is XDG-conventional,
   latter keeps it in the synced repo (but tokens are sensitive).
3. **Multi-account** — one MCP server instance per account, or one server handling multiple?
   Leaning toward env var selecting account, one server instance.
4. **Ergane integration** — build CLI from day one or add later? Probably later.
