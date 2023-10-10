# Changelog

All notable changes to this gem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.1] - 2026-03-31

### Changed
- Standardize README badges, support section, and license format

## [0.6.0] - 2026-03-29

### Added
- Thread-safe connection pooling for reusing Net::HTTP connections (`pool: true`, `pool_size: N`)
- Automatic request ID tracking via `X-Request-ID` header with `SecureRandom.uuid` (persists across retries)
- `Response#request_id` accessor and `request_id:` option to override generated IDs
- In-memory response caching for GET requests with `Cache-Control` support (`cache: true`)
- Conditional requests via `ETag` / `Last-Modified` headers (`If-None-Match` / `If-Modified-Since`)
- `client.clear_cache!` to flush the response cache
- `Pool` class with `checkout`/`checkin` interface and automatic idle connection expiry
- `Cache` class with `lookup`/`store`/`clear!` interface

## [0.5.0] - 2026-03-27

### Added
- Cookie jar with automatic Set-Cookie parsing and per-request Cookie header (`cookies: true` option)
- Proxy support via `proxy:` option or `HTTP_PROXY`/`HTTPS_PROXY` environment variables
- Automatic response decompression for gzip and deflate Content-Encoding
- Configurable redirect following with `follow_redirects:` and `max_redirects:` options
- Redirect chain tracking via `response.redirects` and `response.redirected?`
- Request timing metrics via `response.metrics` (total_time, first_byte_time, dns_time, connect_time, tls_time)
- `CookieJar` class with domain/path matching, expiration, and secure cookie handling
- `Metrics` class for per-request timing breakdown

## [0.4.7] - 2026-03-26

### Fixed
- Add Sponsor badge to README
- Fix license section link format

## [0.4.6] - 2026-03-24

### Changed
- Expand test coverage to 85+ examples covering edge cases and error paths

## [0.4.5] - 2026-03-24

### Fixed
- Fix stray character in CHANGELOG formatting

## [0.4.4] - 2026-03-22

### Changed
- Update rubocop configuration for Windows compatibility

## [0.4.3] - 2026-03-20

### Fixed
- Fix README description trailing period
- Fix CHANGELOG header wording

## [0.4.2] - 2026-03-20

### Fixed
- Fix badge order and Gem Version badge URL in README

## [0.4.1] - 2026-03-18

### Fixed
- Fix RuboCop Style/StringLiterals violations in gemspec

## [0.4.0] - 2026-03-17

### Added

- Custom error hierarchy: `Error`, `TimeoutError`, `NetworkError`, `HttpError` for structured error handling
- Streaming responses via block parameter — yield body chunks instead of buffering entire response
- Multipart form data support via `multipart:` parameter for file uploads
- Per-phase timeouts: `open_timeout:`, `read_timeout:`, `write_timeout:` on constructor and per-request
- Response validation via `expect:` option — auto-raises `HttpError` if status not in expected list

### Changed

- Network errors (`Errno::ECONNREFUSED`, `Errno::ECONNRESET`, etc.) now raise `NetworkError` instead of raw system errors
- Timeout errors (`Net::OpenTimeout`, `Net::ReadTimeout`) now raise `TimeoutError` instead of raw Net errors

## [0.3.3] - 2026-03-16

### Fixed
- Fix CI: version test and rubocop compliance

## [0.3.2] - 2026-03-16

### Changed
- Add License badge to README
- Add bug_tracker_uri to gemspec
- Add Development section to README
- Add Requirements section to README

## [0.3.1] - 2026-03-12

### Fixed
- Re-release with no code changes (RubyGems publish fix)

## [0.3.0] - 2026-03-12

### Added

- `retry_on_status` option to retry on specific HTTP status codes (e.g., 429, 503)
- Form-urlencoded body support via `form:` parameter on POST, PUT, and PATCH
- `bearer_token` helper method for Bearer token authentication
- `basic_auth` helper method for HTTP Basic authentication

### Fixed

- Exponential backoff delay: first retry now uses base delay instead of 2x base delay

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
