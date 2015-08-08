# philiprehberger-http_client

[![Gem Version](https://badge.fury.io/rb/philiprehberger-http_client.svg)](https://badge.fury.io/rb/philiprehberger-http_client)
[![CI](https://github.com/philiprehberger/rb-http-client/actions/workflows/ci.yml/badge.svg)](https://github.com/philiprehberger/rb-http-client/actions/workflows/ci.yml)

Lightweight HTTP client wrapper with retries and interceptors. Zero dependencies — built on Ruby's stdlib `net/http`.

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

### Exponential backoff

```ruby
client = Philiprehberger::HttpClient.new(
  base_url: "https://api.example.com",
  retries: 3,
  retry_delay: 1,
  retry_backoff: :exponential
)
```

### Per-request timeout

```ruby
response = client.get("/slow-endpoint", timeout: 60)
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
| `timeout`     | Integer | `30`    | Read/open timeout in seconds         |
| `retries`     | Integer | `0`     | Retry attempts on network errors     |
| `retry_delay` | Numeric | `1`     | Seconds between retries              |
| `retry_backoff` | String/Symbol | `:fixed` | Backoff strategy — `:fixed` or `:exponential` |

### Methods

| Method | Description |
|--------|-------------|
| `get(path, **opts)` | Send GET request |
| `post(path, **opts)` | Send POST request |
| `put(path, **opts)` | Send PUT request |
| `patch(path, **opts)` | Send PATCH request |
| `delete(path, **opts)` | Send DELETE request |
| `head(path, **opts)` | Send HEAD request |
| `request_count` | Total number of requests made by this client |

### `Response`

| Method    | Returns | Description                     |
|-----------|---------|---------------------------------|
| `status`  | Integer | HTTP status code                |
| `body`    | String  | Raw response body               |
| `headers` | Hash    | Response headers                |
| `ok?`     | Boolean | `true` if status is 200-299     |
| `json`    | Hash    | Parsed JSON body                |

## License

[MIT](LICENSE)
