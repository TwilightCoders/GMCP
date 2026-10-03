# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [0.4.0]

### Fixed

- **`gmail_get_message` and `calendar_get_event` returned an object id instead
  of the record.** `ToolHelpers.json_response` called `to_json` on a
  `Him::Model`, which does not include `ActiveModel::Serializers::JSON`, so the
  call resolved to `Object#to_json` and produced the inspect string —
  `"#<GMCP::Gmail::Message:0x0000000125404b08>"`. That is well-formed JSON
  carrying none of the message, so a caller could not distinguish it from
  success; the tool was unusable for reading mail while appearing to work.
  `json_response` now serializes by `attributes`, recursing through arrays and
  hashes so a collection does not hit the same wall one level down.

- **Decoded message bodies were tagged `ASCII-8BIT`.**
  `Base64.urlsafe_decode64` returns binary regardless of the bytes, which made
  `JSON.generate` warn on json 2.x and will make it raise on 3.0, and rendered
  any non-UTF-8 body as mojibake. Bodies are now transcoded from the charset
  declared on the part's own `Content-Type`, defaulting to UTF-8, with invalid
  bytes replaced rather than raised on. A part claiming UTF-8 is scrubbed
  explicitly, since `String#encode` is a no-op when source and destination
  encodings match and therefore does not clean such a part.

### Changed

- `him` now resolves from RubyGems rather than a git pin. The published
  `him` 0.1.0 is identical to the revision previously pinned, so this changes
  nothing at runtime — but a git-sourced dependency cannot be expressed in a
  gemspec, and it was the only thing preventing `gem install gmcp`.

### Added

- `Gmail::Message#headers` and `#header(name)` — the `{name:, value:}` array
  Gmail returns, flattened to a hash, with case-insensitive lookup. Senders
  disagree about header casing (`Message-ID` / `Message-Id` / `message-id`), so
  an exact-match lookup silently misses.

- `Gmail::Message#body_text` — the body as readable text. Walks the MIME tree
  for `text/plain`, falling back to `text/html` with script and style blocks
  dropped, block tags turned into line breaks, remaining markup stripped and
  entities unescaped. The fallback matters because a large share of mail ships
  no plain part at all.

- `Gmail::Message#to_summary` — the ids needed for follow-up calls, the common
  headers lifted to the top level, every header under `:headers`, and a decoded
  body. `gmail_get_message` now returns this instead of the raw payload, so
  callers no longer hand-decode base64url MIME leaves to read a message.

## [0.3.1]

### Fixed

- **Setup instructions pointed at the wrong file and the wrong variable.**
  README told you to register the server in `settings.json`; MCP servers are
  configured in `.claude.json`, and which `.claude.json` depends on
  `CLAUDE_CONFIG_DIR`. A registration written to the wrong one is not reported
  as an error — the server simply never appears in `claude mcp list`, and every
  session runs without it. Step 3 now uses `claude mcp add`, which resolves the
  config directory itself, and shows `--scope project` as the way to widen one
  repo's grant past the machine default.

- The same section's examples used `GMCP_ACCOUNT` (singular), which is only a
  legacy fallback, and presented one process per account as the way to serve
  several accounts. One process serves them all via `GMCP_ACCOUNTS`; separate
  processes are for separating *capabilities*, which is what the rest of the
  README already said.

- Startup notice said "voice.read reach the voice principal" when exactly one
  unscoped capability was granted.

### Added

- README documents that the OAuth consent screen must be published. Left in
  **Testing**, Google expires every refresh token after 7 days, so accounts stop
  working about a week after authorization with `invalid_grant` and nothing
  explains why. Also records what publishing does *not* do: an unverified
  production app still shows the "Google hasn't verified this app" interstitial,
  and verifying the restricted `gmail.modify` scope needs an annual third-party
  security assessment not worth doing for a personal install.

- README notes that a version-manager shim (with `RBENV_DIR`) should be
  preferred over a versioned Ruby path, so a Ruby upgrade does not break every
  session at once.

### Removed

- `SKETCH.md`, the pre-implementation design sketch. Every open question in it
  has been answered and several of its particulars are now wrong — `token.json`
  (it is `token.yaml`), a `cli.rb` that was never built, and an architecture
  tree predating `capabilities.yml`, `api_binding.rb` and the whole Voice
  module. README and CHANGELOG carry the current truth.

## [0.3.0]

### Fixed

- **One process can now safely serve more than one account.** The active
  account was written onto the model classes themselves (`him`'s `use_api`
  stores a class-level ivar), so `with_account` mutated process-global state.
  Two concurrent tool calls for different accounts raced, and the second could
  execute against the first's mailbox. Isolation depended on never running two
  at once, which is not isolation.

  `GMCP::ApiBinding` binds each model to a *resolver* once — `him` resolves
  `use_api` at request time and calls it if it responds to `:call` — and swaps
  the account per fiber. `Server.with_account` scopes the binding to a block
  and restores the previous one, so nesting cannot leak an account to its
  caller. No change to `him` was required.

  A request with nothing bound now raises `ApiBinding::NotBound` instead of
  falling back to whatever the previous caller left behind.

### Changed

- `AccountRegistry` gains `apis_for` and `scoped`; `activate` is kept for
  callers with no natural block extent. `bind_models!` is gone.
- README no longer states that per-process isolation is required for account
  separation. It remains required for *capability* separation, since
  `GMCP_CAPABILITIES` is read once at startup.

## [0.2.0]

### Added

- **Capability scoping.** `GMCP_CAPABILITIES` gates tool *registration*: a tool
  whose capability was not granted is never defined on the MCP server, so it
  never appears in `tools/list` and cannot be called regardless of what the
  client sends. `config/capabilities.yml` is the source of truth and a spec
  asserts it matches the tools actually registered, so it cannot drift.
  - **`GMCP_CAPABILITIES` unset means every capability; set-but-empty means
    none.** An automated launcher must always set it explicitly — omitting the
    key when there are no grants fails open.
- **Per-connector `account_scoping` and `credential_source`.** GMCP serves
  several connectors that do not share account semantics. Gmail, Calendar and
  Drive are `enforced` / `local_file`; Voice is `ignored` / `delegated`, because
  its principal is whichever account Safari holds and `GMCP_ACCOUNTS` cannot
  narrow it.
- **Gmail pagination.** `gmail_search` accepts and returns a `page_token`;
  `Message.search_page` and `Message.each_page` expose the cursor that
  `get_collection` discards.
- **Gmail batch operations.** `gmail_batch_archive`, `gmail_batch_trash` and
  `gmail_batch_modify` act on up to 1000 messages per request.
- **Gmail attachments.** `gmail_list_attachments` and
  `gmail_download_attachment`, the latter under its own `gmail.download`
  capability. The destination directory is required, filenames are reduced to a
  basename so they cannot escape it, and existing files are never overwritten.
- **RFC 8058 one-click unsubscribe** under `gmail.unsubscribe`. The target URL
  comes from the message's own `List-Unsubscribe` header and cannot be passed
  in; https only; refuses to act unless the sender advertises
  `List-Unsubscribe-Post`.
- **Google Voice support** (macOS only) — list, search, archive, mark read, and
  trash. There is no usable OAuth path for Voice, so this reads Safari's session
  cookies. `voice_account` reports which account those cookies resolve to.
- `AccountRegistry`, extracting per-account API state out of `Server`.
- `ToolHelpers`, and a `with_account { }` block replacing the repeated
  `next auth_err if auth_err` guard in every tool.
- `bin/gmail_survey`, a read-only per-sender inbox survey for triage.
- `GMCP_CREDENTIALS_FILE` to override the `credentials.json` location.

### Changed

- `bin/gmcp` prints its account list and capability set to stderr at startup,
  and warns when a granted capability belongs to a connector that ignores
  account scoping.
- `gmcp_authorize` passes `login_hint`, so the consent screen pre-selects the
  requested account instead of letting a different signed-in account be
  authorized under its name.

### Fixed

- A revoked or expired refresh token no longer crashes the server at startup.
  The account is left unbound and reports that it needs re-authorizing.
- `bin/gmcp-auth` was broken twice over: it referenced a constant removed during
  a refactor, and drove Google's out-of-band flow, which was retired in 2022. It
  now uses the same loopback redirect as `gmcp_authorize`, and verifies the
  stored token works before reporting success.
- Voice now fails with a readable message on a host that cannot supply Safari
  cookies, instead of letting `Errno::ENOENT` escape as an MCP internal error.
- Voice tools were entirely non-functional — a keyword/positional mismatch in
  the session constructor raised on every call.
- Batch id handling no longer passes whitespace-only ids through to Gmail.
- `bin/gmail_survey` and `bin/gmcp-auth` set `$stdout.sync`, so progress is
  visible when stdout is a pipe.

### Removed

- Voice tools no longer accept an `account:` parameter. Voice authenticates with
  Safari's cookies, so the parameter could not select anything.

## [0.1.0]

- Initial scaffold: Gmail, Calendar and Drive tools over the `him` REST ORM and
  the official `mcp` Ruby SDK.
