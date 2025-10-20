# philiprehberger-http_client

[![Tests](https://github.com/philiprehberger/rb-http-client/actions/workflows/ci.yml/badge.svg)](https://github.com/philiprehberger/rb-http-client/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/philiprehberger-http_client.svg)](https://rubygems.org/gems/philiprehberger-http_client)
[![Last updated](https://img.shields.io/github/last-commit/philiprehberger/rb-http-client)](https://github.com/philiprehberger/rb-http-client/commits/main)

Lightweight HTTP client wrapper with retries and interceptors

## Requirements

- Ruby >= 3.1

## Installation

Add to your Gemfile:

```ruby
gem "philiprehberger-http_client"
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install philiprehberger-http_client
```

## Usage

```ruby
require "philiprehberger/http_client"

client = Philiprehberger::HttpClient.new(base_url: "https://api.example.com")

response = client.get("/users", params: { page: 1 })
puts response.status  # => 200
puts response.ok?     # => true
puts response.json    # => [{"id" => 1, "name" => "Alice"}, ...]
```

### POST with JSON body

```ruby
response = client.post("/users", json: { name: "Bob", email: "bob@example.com" })

puts response.status  # => 201
puts response.json    # => {"id" => 2, "name" => "Bob", ...}
```

### Default headers

```ruby
client = Philiprehberger::HttpClient.new(
  base_url: "https://api.example.com",
  headers: { "Authorization" => "Bearer token123" }
)
```

### Interceptors

Add request/response interceptors to log, modify, or inspect traffic:

```ruby
client = Philiprehberger::HttpClient.new(base_url: "https://api.example.com")

client.use do |context|
  if context[:response]
    puts "Response: #{context[:response].status}"
  else
    puts "Request: #{context[:request][:method]} #{context[:request][:uri]}"
  end
end

client.get("/health")
# Prints:
#   Request: GET https://api.example.com/health
#   Response: 200
```

### Form data

```ruby
response = client.post("/login", form: { username: "alice", password: "secret" })
# Content-Type: application/x-www-form-urlencoded is set automatically
```

### File uploads (multipart)

Upload files using multipart/form-data:

```ruby
response = client.post("/upload", multipart: {
  file: File.open("photo.jpg"),
  name: "vacation"
})
# Content-Type: multipart/form-data is set automatically with boundary
```

Both `File` objects and string values are supported. Files are sent with their filename and `application/octet-stream` content type.

### Streaming responses

Stream large responses without buffering the entire body in memory:

```ruby
File.open("download.bin", "wb") do |file|
  client.get("/large-file") do |chunk|
    file.write(chunk)
  end
end
# Returns a Response with body: nil and streaming?: true
```

### Authentication helpers

```ruby
# Bearer token
client.bearer_token("your-api-token")
client.get("/protected")  # Authorization: Bearer your-api-token

# Basic auth
client.basic_auth("username", "password")
client.get("/protected")  # Authorization: Basic dXNlcm5hbWU6cGFzc3dvcmQ=
```

### Error handling

All errors inherit from `Philiprehberger::HttpClient::Error`:

```ruby
begin
  client.get("/api/data")
rescue Philiprehberger::HttpClient::TimeoutError => e
  puts "Request timed out: #{e.message}"
rescue Philiprehberger::HttpClient::NetworkError => e
  puts "Network error: #{e.message}"
rescue Philiprehberger::HttpClient::HttpError => e
  puts "HTTP error: #{e.response.status}"
rescue Philiprehberger::HttpClient::Error => e
  puts "Client error: #{e.message}"
end
```

### Response validation

Auto-raise `HttpError` if the response status doesn't match expected values:

```ruby
# Raises HttpError if status is not 200
response = client.get("/api/users", expect: [200])

# Accept multiple status codes
response = client.post("/api/users", json: data, expect: [200, 201])
```

### Timeouts

Set a general timeout or per-phase timeouts:

```ruby
# General timeout (applies to open, read, and write)
client = Philiprehberger::HttpClient.new(base_url: "https://api.example.com", timeout: 30)

# Per-phase timeouts (override general timeout)
client = Philiprehberger::HttpClient.new(
  base_url: "https://api.example.com",
  open_timeout: 5,
  read_timeout: 30,
  write_timeout: 10
)

# Per-request timeout overrides
response = client.get("/slow-endpoint", read_timeout: 120)
response = client.post("/upload", body: data, write_timeout: 60)
```

### Retries

Automatically retry on network errors (connection refused, timeouts, etc.):

```ruby
client = Philiprehberger::HttpClient.new(
  base_url: "https://api.example.com",
  retries: 3,
  retry_delay: 2
)

response = client.get("/unstable-endpoint")
```

You can also retry on specific HTTP status codes:

```ruby
client = Philiprehberger::HttpClient.new(
  base_url: "https://api.example.com",
  retries: 3,
  retry_delay: 1,
  retry_on_status: [429, 503]
)
```

### Exponential backoff

```ruby
client = Philiprehberger::HttpClient.new(
  base_url: "https://api.example.com",
  retries: 3,
  retry_delay: 1,
  retry_backoff: :exponential
)
# Delay sequence: 1s, 2s, 4s
```

### Cookie jar

Enable automatic cookie handling across requests:

```ruby
client = Philiprehberger::HttpClient.new(
  base_url: "https://app.example.com",
  cookies: true
)

# Login — server sends Set-Cookie header, cookie jar stores it
client.post("/login", form: { user: "alice", pass: "secret" })

# Subsequent requests automatically include the session cookie
client.get("/dashboard")  # Cookie: session=abc123

# Inspect stored cookies
client.cookie_jar.size  # => 1
client.cookie_jar.to_a  # => [#<Cookie name="session" ...>]
client.cookie_jar.clear # remove all cookies
```

### Proxy support

Route requests through an HTTP proxy:

```ruby
# Explicit proxy
client = Philiprehberger::HttpClient.new(
  base_url: "https://api.example.com",
  proxy: "http://proxy.corp.net:8080"
)

# Or set HTTP_PROXY / HTTPS_PROXY environment variables
# and the client auto-detects them
client = Philiprehberger::HttpClient.new(base_url: "https://api.example.com")
```

### Response compression

Gzip and deflate responses are decompressed automatically. The client sends `Accept-Encoding: gzip, deflate` by default:

```ruby
response = client.get("/large-payload")
response.body  # already decompressed, regardless of Content-Encoding
```

### Redirect following

Redirects are followed automatically (up to 5 by default):

```ruby
# Customize redirect behavior
client = Philiprehberger::HttpClient.new(
  base_url: "https://example.com",
  max_redirects: 3,
  follow_redirects: true  # default
)

response = client.get("/old-page")
response.redirected?  # => true
response.redirects    # => ["https://example.com/new-page"]

# Disable redirect following
client = Philiprehberger::HttpClient.new(
  base_url: "https://example.com",
  follow_redirects: false
)
```

### Request metrics

Access timing breakdown for each request:

```ruby
response = client.get("/api/data")
metrics = response.metrics

metrics.total_time       # => 0.234 (seconds)
metrics.first_byte_time  # => 0.180
metrics.to_h             # => { dns_time: 0.0, connect_time: 0.0, ... }
```

> **Note:** `dns_time`, `connect_time`, and `tls_time` are not available from Ruby's stdlib `Net::HTTP` and will always be `0.0`. Only `total_time` and `first_byte_time` are populated.

### Connection pooling

Reuse TCP connections to the same host for better performance:

```ruby
client = Philiprehberger::HttpClient.new(
  base_url: "https://api.example.com",
  pool: true,       # enable connection pooling
  pool_size: 10     # max connections per host (default: 5)
)

# Connections are automatically reused across requests
10.times { client.get("/data") }  # reuses the same connection

# Drain all pooled connections
client.pool.drain
```

### Client lifecycle

Use `Client.open` for automatic cleanup, or call `close` manually to drain the connection pool:

```ruby
# Block form — pool is drained automatically
Philiprehberger::HttpClient.open(base_url: "https://api.example.com", pool: true) do |client|
  client.get("/data")
  client.post("/submit", json: { key: "value" })
end

# Manual form
client = Philiprehberger::HttpClient.new(base_url: "https://api.example.com", pool: true)
client.get("/data")
client.close  # drains the connection pool
```

### Request ID tracking

Every request is assigned a unique `X-Request-ID` header automatically:

```ruby
response = client.get("/api/data")
response.request_id  # => "550e8400-e29b-41d4-a716-446655440000"

# Override with a custom request ID
response = client.get("/api/data", request_id: "my-custom-id")
response.request_id  # => "my-custom-id"

# The same request ID is preserved across retries
client = Philiprehberger::HttpClient.new(
  base_url: "https://api.example.com",
  retries: 3
)
response = client.get("/unstable")
response.request_id  # same ID used for all retry attempts
```

### Response caching

Cache GET responses in memory with automatic `Cache-Control` support:

```ruby
client = Philiprehberger::HttpClient.new(
  base_url: "https://api.example.com",
  cache: true
)

# First request hits the server
response = client.get("/data")

# Second request returns cached response (if within max-age)
response = client.get("/data")

# Conditional requests: sends If-None-Match / If-Modified-Since
# when cache entry has ETag or Last-Modified

# Flush the cache
client.clear_cache!
```

### Request logging callback

Add an `on_request` callback for observability — it receives the HTTP method, URI, response status, and duration (in seconds) after each request completes:

```ruby
client = Philiprehberger::HttpClient.new(
  base_url: "https://api.example.com",
  on_request: ->(method, uri, status, duration) {
    puts "#{method} #{uri} -> #{status} (#{duration.round(3)}s)"
  }
)

client.get("/users")
# Prints: GET https://api.example.com/users -> 200 (0.234s)
```

### All HTTP methods

```ruby
client.get("/resource", params: { q: "search" })
client.post("/resource", json: { key: "value" })
client.put("/resource/1", json: { key: "updated" })
client.patch("/resource/1", json: { key: "patched" })
client.delete("/resource/1")
client.head("/resource")
```

## API

### `Philiprehberger::HttpClient.new(**options)`

| Option        | Type    | Default | Description                          |
|---------------|---------|---------|--------------------------------------|
| `base_url`    | String  | —       | Base URL for all requests (required) |
| `headers`     | Hash    | `{}`    | Default headers for every request    |
| `timeout`     | Integer | `30`    | General timeout in seconds           |
| `open_timeout` | Integer | `nil`  | TCP connection timeout (overrides `timeout`) |
| `read_timeout` | Integer | `nil`  | Response read timeout (overrides `timeout`)  |
| `write_timeout` | Integer | `nil` | Request write timeout (overrides `timeout`)  |
| `retries`     | Integer | `0`     | Retry attempts on network errors     |
| `retry_delay` | Numeric | `1`     | Seconds between retries              |
| `retry_backoff` | Symbol | `:fixed` | Backoff strategy — `:fixed` or `:exponential` |
| `retry_on_status` | Array | `nil` | HTTP status codes to retry on (e.g., `[429, 503]`) |
| `cookies` | Boolean | `false` | Enable cookie jar for automatic cookie handling |
| `proxy` | String | `nil` | Proxy URL (also reads `HTTP_PROXY`/`HTTPS_PROXY` env vars) |
| `follow_redirects` | Boolean | `true` | Follow 3xx redirects automatically |
| `max_redirects` | Integer | `5` | Maximum number of redirects to follow |
| `pool` | Boolean | `false` | Enable connection pooling |
| `pool_size` | Integer | `5` | Maximum connections per host:port |
| `cache` | Boolean | `false` | Enable in-memory GET response caching |
| `on_request` | Proc | `nil` | Callback invoked after each request with `(method, uri, status, duration)` |

### Methods

| Method | Description |
|--------|-------------|
| `get(path, **opts, &block)` | Send GET request (block enables streaming) |
| `post(path, **opts, &block)` | Send POST request |
| `put(path, **opts, &block)` | Send PUT request |
| `patch(path, **opts, &block)` | Send PATCH request |
| `delete(path, **opts)` | Send DELETE request |
| `head(path, **opts)` | Send HEAD request |
| `request_count` | Total number of requests made by this client |
| `cookie_jar` | Returns the `CookieJar` instance (nil if cookies disabled) |
| `bearer_token(token)` | Set Bearer token auth for all subsequent requests |
| `basic_auth(user, pass)` | Set Basic auth for all subsequent requests |
| `clear_cache!` | Flush the response cache |
| `close` | Drain the connection pool (no-op if pooling disabled) |
| `self.open(**opts, &block)` | Block form — creates client, yields it, ensures `close` is called |
| `pool` | Returns the `Pool` instance (nil if pooling disabled) |
| `cache` | Returns the `Cache` instance (nil if caching disabled) |

### Per-request options

| Option | Type | Description |
|--------|------|-------------|
| `params` | Hash | Query parameters (GET, HEAD) |
| `json` | Hash/Array | JSON body (POST, PUT, PATCH) |
| `form` | Hash | Form-urlencoded body (POST, PUT, PATCH) |
| `multipart` | Hash | Multipart form data with file support (POST, PUT, PATCH) |
| `body` | String | Raw body string (POST, PUT, PATCH) |
| `headers` | Hash | Per-request headers |
| `timeout` | Integer | General per-request timeout |
| `open_timeout` | Integer | Per-request open timeout |
| `read_timeout` | Integer | Per-request read timeout |
| `write_timeout` | Integer | Per-request write timeout |
| `expect` | Array | Expected status codes — raises `HttpError` otherwise |
| `request_id` | String | Custom request ID (auto-generated UUID if omitted) |

### `Response`

| Method    | Returns | Description                     |
|-----------|---------|---------------------------------|
| `status`  | Integer | HTTP status code                |
| `body`    | String  | Raw response body (`nil` if streamed) |
| `headers` | Hash    | Response headers                |
| `ok?`     | Boolean | `true` if status is 200-299     |
| `json`    | Hash    | Parsed JSON body                |
| `streaming?` | Boolean | `true` if response was streamed |
| `metrics` | Metrics | Request timing breakdown (total_time, first_byte_time, etc.) |
| `redirects` | Array | Redirect chain URLs (empty if no redirects) |
| `redirected?` | Boolean | `true` if response was redirected |
| `request_id` | String | Request ID for this request |

### Errors

| Class | Description |
|-------|-------------|
| `Error` | Base error class (inherits `StandardError`) |
| `ConfigurationError` | Invalid client option (negative timeout, bad retry config, etc.) |
| `TimeoutError` | Connection or read timeout |
| `NetworkError` | Connection refused, reset, unreachable |
| `HttpError` | Response status mismatch (has `.response` accessor) |

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## Support

If you find this project useful:

⭐ [Star the repo](https://github.com/philiprehberger/rb-http-client)

🐛 [Report issues](https://github.com/philiprehberger/rb-http-client/issues?q=is%3Aissue+is%3Aopen+label%3Abug)

💡 [Suggest features](https://github.com/philiprehberger/rb-http-client/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement)

❤️ [Sponsor development](https://github.com/sponsors/philiprehberger)

🌐 [All Open Source Projects](https://philiprehberger.com/open-source-packages)

💻 [GitHub Profile](https://github.com/philiprehberger)

🔗 [LinkedIn Profile](https://www.linkedin.com/in/philiprehberger)

## License

[MIT](LICENSE)
