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

**Gmail (9 tools)**
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

### 3. Wire up Claude Code

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

### 4. Authorize from Claude

Once the server is wired up, ask Claude to call `gmcp_authorize`. It will return a URL — open it in your browser, approve access, copy the code, then call `gmcp_authorize` again with the code. Tokens are stored at `~/.config/gmcp/<account>/token.yaml` and auto-refresh on subsequent runs.

## Multiple accounts and capability scoping

GMCP is scoped along two independent axes. Both are environment variables read
once at process start, so a given `bin/gmcp` process has a fixed, inspectable
reach — it prints both to stderr on startup.

### `GMCP_ACCOUNTS` — which mailboxes

Comma-separated. Each account keeps its own OAuth token at
`~/.config/gmcp/<account>/token.yaml`, and every Gmail/Calendar/Drive tool takes
an optional `account:` argument selecting among them (defaulting to the first).

```sh
GMCP_ACCOUNTS=personal@example.com,work@example.com bin/gmcp
```

Authorize each one separately with `gmcp_authorize(account: "...")`.

### `GMCP_CAPABILITIES` — which verbs

Comma-separated capability names from `config/capabilities.yml`. Capabilities
gate **registration**: a tool whose capability was not granted is never defined
on the MCP server, so it never appears in `tools/list` and cannot be called no
matter what the client sends.

```sh
# a read-only assistant
GMCP_CAPABILITIES=gmail.read,calendar.read bin/gmcp

# one that may also send
GMCP_CAPABILITIES=gmail.read,gmail.send bin/gmcp
```

| Capability | Grants |
|---|---|
| `gmcp.authorize` | Start the OAuth flow (opens a browser) |
| `gmail.read` | Search (paginated), read, list labels, list attachments, inspect unsubscribe options |
| `gmail.modify_labels` | Add/remove labels and archive, single or batched (archiving *is* removing `INBOX`) |
| `gmail.trash` | Trash a message, single or batched |
| `gmail.send` | Send, draft, reply |
| `gmail.download` | Write attachment bytes to a local directory |
| `gmail.unsubscribe` | RFC 8058 one-click unsubscribe — leaves Google, tells a third party the address is live |
| `calendar.read` | List calendars, read events |
| `calendar.write` | Create, update, RSVP |
| `calendar.delete` | Delete an event |
| `drive.read` | Search, list folders, read files |
| `voice.read` | List/search Voice; report which account Safari resolves to |
| `voice.modify` | Archive, mark read/unread |
| `voice.trash` | Trash a Voice message |

`config/capabilities.yml` is the source of truth; a spec asserts it matches the
tools actually registered, so it cannot silently drift.

### Bulk work

`gmail_search` paginates. It returns a `page_token` whenever more results exist;
pass it back to walk a whole mailbox. In Ruby, `Message.each_page` handles the
cursor for you and is bounded by `max_pages` so a runaway cursor cannot spin.

```ruby
GMCP::Gmail::Message.each_page('in:inbox', max_results: 500) do |page|
  page[:messages].each { |m| ... }
end
```

Acting on the result is batched — `gmail_batch_archive`, `gmail_batch_trash`,
and `gmail_batch_modify` take up to 1000 ids in one request rather than one
round trip per message. Gmail returns nothing per-message, so a partial failure
is not distinguishable; re-read if you need per-message confirmation.

Attachments are two steps: `gmail_list_attachments` (under `gmail.read`) gives
you filenames and ids, `gmail_download_attachment` (under `gmail.download`)
writes one to a directory you name. There is no default destination, the
filename is reduced to a basename so it cannot escape that directory, and an
existing file is never overwritten.

### Contract: unset and empty mean opposite things

This distinction is the whole security boundary. It is not a convenience.

| Value | Meaning |
|---|---|
| `GMCP_CAPABILITIES` **not set** | **Every** capability. For a human running `bin/gmcp` by hand with no grant system in front of it. |
| `GMCP_CAPABILITIES=""` | **No** capabilities. The explicit empty grant set for an identity that was granted nothing. |

**An automated launcher must always set the variable explicitly, including when
the grant set is empty.** Omitting the key because there are no grants fails
open and hands the process everything. There is no wildcard value, and unknown
entries are dropped rather than trusted, so a grant cannot widen itself by typo.

### Per-process isolation is required, not optional

One process cannot safely serve two identities. GMCP binds the active account
into process-global state — `him`'s `use_api` writes a class-level ivar on
`Gmail::Message` and friends — so `with_account` mutates a shared global rather
than establishing isolation. Scope by **spawning one GMCP process per (identity,
account set)** with `GMCP_ACCOUNTS` and `GMCP_CAPABILITIES` set for that
identity. Do not run a shared instance and scope per call.

### Connectors and account scoping

the host models `gmail`, `google_calendar`, `drive`, and `voice` as separate
connectors. One GMCP process serves all of them, and **they do not share account
semantics.** Each declares which it has in `config/capabilities.yml`:

| Connector | `account_scoping` | `credential_source` | `GMCP_ACCOUNTS` constrains it? |
|---|---|---|---|
| `gmcp` | `enforced` | `local_file` | yes |
| `gmail` | `enforced` | `local_file` | yes |
| `google_calendar` | `enforced` | `local_file` | yes |
| `drive` | `enforced` | `local_file` | yes |
| `voice` | **`ignored`** | `delegated` | **no** |

Voice has no usable OAuth path — the token-to-cookie exchange is reserved for
Chromium — so `GMCP::Voice::Session` authenticates with the session cookies
Safari already holds. Its principal is **whichever Google account is signed in to
Safari**, resolved at call time by a browser GMCP does not control.
`GMCP_ACCOUNTS` cannot narrow it.

This matters beyond GMCP. In a grant model where the account column is the unit
of scoping, a Voice grant reads as scoped and is not: the `connector_account` on
it is decorative. That is why `account_scoping` is a field a UI can read rather
than a note — an `ignored` grant should be rendered as the principal it actually
reaches ("whichever account Safari holds"), never as the account named on the
row. `bin/gmcp` prints the same warning at startup for any granted capability
whose connector ignores scoping.

Call `voice_account` to observe which account that currently is.

## Development

```bash
bundle install
bundle exec rake spec
```

Ruby 3.4.9+ required.

## License

MIT. See `LICENSE.txt`.
