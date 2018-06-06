# philiprehberger-http_client

[![Gem Version](https://badge.fury.io/rb/philiprehberger-http_client.svg)](https://badge.fury.io/rb/philiprehberger-http_client)
[![CI](https://github.com/philiprehberger/rb-http-client/actions/workflows/ci.yml/badge.svg)](https://github.com/philiprehberger/rb-http-client/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/philiprehberger/rb-http-client)](LICENSE)

Lightweight HTTP client wrapper with retries and interceptors. Zero dependencies — built on Ruby's stdlib `net/http`.

## Requirements

- Ruby >= 3.1

## Installation

Add to your Gemfile:

```ruby
gem "philiprehberger-http_client"
```

Or install directly:

```sh
gem install philiprehberger-http_client
```

## Usage

```ruby
require "philiprehberger/http_client"

client = Philiprehberger::HttpClient.new(base_url: "https://api.example.com")
```

### GET request

```ruby
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

Streaming works with all HTTP methods that accept a block:

```ruby
client.post("/export", json: { format: "csv" }) do |chunk|
  output.write(chunk)
end
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

- `TimeoutError` — raised on `Net::OpenTimeout` and `Net::ReadTimeout`
- `NetworkError` — raised on connection refused, reset, host unreachable, etc.
- `HttpError` — raised when response status doesn't match `expect:` list (includes `.response`)

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

> **Note:** Network error retries and HTTP status retries both count toward the same retry limit.

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
| `bearer_token(token)` | Set Bearer token auth for all subsequent requests |
| `basic_auth(user, pass)` | Set Basic auth for all subsequent requests |

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

### `Response`

| Method    | Returns | Description                     |
|-----------|---------|---------------------------------|
| `status`  | Integer | HTTP status code                |
| `body`    | String  | Raw response body (`nil` if streamed) |
| `headers` | Hash    | Response headers                |
| `ok?`     | Boolean | `true` if status is 200-299     |
| `json`    | Hash    | Parsed JSON body                |
| `streaming?` | Boolean | `true` if response was streamed |

### Errors

| Class | Description |
|-------|-------------|
| `Error` | Base error class (inherits `StandardError`) |
| `TimeoutError` | Connection or read timeout |
| `NetworkError` | Connection refused, reset, unreachable |
| `HttpError` | Response status mismatch (has `.response` accessor) |


## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## License

[MIT](LICENSE)
