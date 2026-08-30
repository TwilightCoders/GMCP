# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

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
