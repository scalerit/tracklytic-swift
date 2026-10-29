# Changelog

## 2.0.0 - 2026-10-30

### Added

- Pipeline creation responses, step dependencies, follow-up steps, timeout configuration, step updates and interactive step actions.
- Event badges, severity, status, logs, action confirmation, retry, expiration and run limits.
- Profile identification, avatars and avatar removal; insight writes and increments.
- User-authorized event, profile and insight queries and management.
- Separate user access JWT configuration, custom API base URL and URLSession injection.
- HTTP error status, server message and raw response body.
- Request contract tests covering async and existing Combine event APIs.

### Changed

- Event tags support nested JSON, arrays, numbers, booleans and null through `AnyCodable`.
- Timestamps are transmitted as Unix milliseconds.
- Link components omit execution arrays; action responses preserve partial failure details.
- `track` keeps its Boolean return value; `createEvent` and `createPipeline` return server creation metadata.

### Removed

- Event `icon`; use `badge` and `logLevel` instead.

### Fixed

- Canonical `userId` encoding replaces `user_id`.
- Encoding failures are propagated without sending an empty request body.
- Missing user credentials cannot fall back to a project API token.
