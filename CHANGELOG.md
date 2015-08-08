# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-03-12

### Added

- `head` HTTP method
- Per-request `timeout:` option on all request methods
- Exponential backoff strategy via `retry_backoff: :exponential`
- `request_count` accessor for tracking total requests made

## [0.1.0] - 2026-03-10

### Added

- Initial release
- HTTP methods: GET, POST, PUT, PATCH, DELETE
- Automatic retries on network errors with configurable delay
- Request/response interceptors via `use` block
- JSON request and response helpers
- Response wrapper with `ok?` and `json` convenience methods
- Zero dependencies — built on Ruby stdlib `net/http`

[0.2.0]: https://github.com/philiprehberger/rb-http-client/releases/tag/v0.2.0
[0.1.0]: https://github.com/philiprehberger/rb-http-client/releases/tag/v0.1.0
