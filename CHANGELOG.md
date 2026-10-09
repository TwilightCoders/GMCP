# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [0.5.0]

### Fixed

- Access tokens refresh while the server runs; calls no longer start failing after an hour.
- Failed Google API calls return an error instead of reporting success.
- Every tool reports failures as an MCP error with the cause.
- Token files are owner-only, and none are created for accounts that were never authorized.
- The OAuth callback listens on loopback only and requires the flow's `state`.
- `gmcp_authorize` accepts only accounts in `GMCP_ACCOUNTS`.
- `bin/gmcp-auth` reports a failed authorization immediately.
- `gmail_reply` threads correctly and answers `Reply-To`.
- Outgoing mail rejects header injection and encodes non-ASCII subjects and names.
- `calendar_rsvp` works, and honors `calendar_id`.
- Calendars whose ids contain `#` (holidays, contacts) are reachable.
- `calendar_get_event` honors `calendar_id`.
- `drive_read_file` reads Docs, Sheets and Slides (exported as text or CSV) and plain text files.
- `voice_list` and `voice_search` work on the current Voice API.
- A rejected Voice session recovers on the next call.

### Changed

- `gmail_search` returns date, sender and subject for each message.
- `gmail_list_attachments` returns a `part_id`; downloads keep their filenames.
- `calendar_list_events` defaults to upcoming events and shows readable start times.
- Calendar events accept `YYYY-MM-DD` for all-day events and an optional `time_zone`; attendees receive invitations.
- `calendar_list_events`, `drive_search` and `drive_list_folder` return a `page_token` when more results exist.
- Drive search and listing include shared drives.
- Voice reads its session from the Chrome profile signed in as the account. Voice tools take `account:` and are limited to `GMCP_ACCOUNTS`. No Safari or Full Disk Access needed.
- `voice_mark_read` takes a `thread_id`.

### Removed

- `voice_archive`, `voice_delete` and the `voice.trash` capability.
- Safari cookie support.

## [0.4.0]

### Fixed

- `gmail_get_message` and `calendar_get_event` return the record instead of an object id.
- Message bodies decode to UTF-8 using the part's declared charset.

### Added

- `gmail_get_message` returns decoded headers and body text.
- `Gmail::Message#headers`, `#header`, `#body_text` and `#to_summary`.

### Changed

- `him` resolves from RubyGems, so `gem install gmcp` works.

## [0.3.1]

### Fixed

- Setup instructions register the server with `claude mcp add` and use `GMCP_ACCOUNTS`.

### Added

- README covers publishing the OAuth app, which avoids weekly re-authorization.

## [0.3.0]

### Fixed

- One process serves several accounts safely; concurrent calls for different accounts no longer interfere.

## [0.2.0]

### Added

- Capability scoping with `GMCP_CAPABILITIES`; ungranted tools are never registered.
- Gmail pagination, batch archive/trash/modify, attachments and one-click unsubscribe.
- Google Voice support (macOS).
- `bin/gmail_survey`, a read-only per-sender inbox survey.
- `GMCP_CREDENTIALS_FILE` to override the `credentials.json` location.

### Changed

- `bin/gmcp` prints its accounts and capabilities at startup.
- `gmcp_authorize` pre-selects the requested account on the consent screen.

### Fixed

- A revoked refresh token no longer stops the server from starting.
- `bin/gmcp-auth` works with Google's current OAuth flow.

## [0.1.0]

- Gmail, Calendar and Drive tools.
