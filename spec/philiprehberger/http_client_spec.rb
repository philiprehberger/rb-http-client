# frozen_string_literal: true

require "spec_helper"

RSpec.describe Philiprehberger::HttpClient do
  let(:base_url) { "https://api.example.com" }
  let(:client) { described_class.new(base_url: base_url) }

  describe ".new" do
    it "returns a Client instance" do
      expect(client).to be_a(Philiprehberger::HttpClient::Client)
    end
  end

  describe "VERSION" do
    it "has a version number" do
      expect(Philiprehberger::HttpClient::VERSION).to eq("0.3.1")
    end
  end

  describe "GET requests" do
    it "performs a simple GET request" do
      stub_request(:get, "https://api.example.com/users")
        .to_return(status: 200, body: '[{"id":1}]', headers: { "content-type" => "application/json" })

      response = client.get("/users")

      expect(response.status).to eq(200)
      expect(response.ok?).to be(true)
      expect(response.json).to eq([{ "id" => 1 }])
    end

    it "sends query parameters" do
      stub_request(:get, "https://api.example.com/users?page=2&per_page=10")
        .to_return(status: 200, body: "[]")

      response = client.get("/users", params: { page: 2, per_page: 10 })

      expect(response.status).to eq(200)
    end

    it "includes default headers" do
      client_with_headers = described_class.new(
        base_url: base_url,
        headers: { "Authorization" => "Bearer token123" }
      )

      stub_request(:get, "https://api.example.com/me")
        .with(headers: { "Authorization" => "Bearer token123" })
        .to_return(status: 200, body: "{}")

      response = client_with_headers.get("/me")

      expect(response.status).to eq(200)
    end
  end

  describe "POST requests" do
    it "sends a JSON body" do
      stub_request(:post, "https://api.example.com/users")
        .with(
          body: '{"name":"Alice"}',
          headers: { "content-type" => "application/json" }
        )
        .to_return(status: 201, body: '{"id":1,"name":"Alice"}')

      response = client.post("/users", json: { name: "Alice" })

      expect(response.status).to eq(201)
      expect(response.json).to eq({ "id" => 1, "name" => "Alice" })
    end

    it "sends a raw body" do
      stub_request(:post, "https://api.example.com/data")
        .with(body: "raw content")
        .to_return(status: 200, body: "ok")

      response = client.post("/data", body: "raw content")

      expect(response.status).to eq(200)
      expect(response.body).to eq("ok")
    end
  end

  describe "PUT requests" do
    it "sends a JSON PUT request" do
      stub_request(:put, "https://api.example.com/users/1")
        .with(body: '{"name":"Updated"}', headers: { "content-type" => "application/json" })
        .to_return(status: 200, body: '{"id":1,"name":"Updated"}')

      response = client.put("/users/1", json: { name: "Updated" })

      expect(response.status).to eq(200)
    end
  end

  describe "PATCH requests" do
    it "sends a JSON PATCH request" do
      stub_request(:patch, "https://api.example.com/users/1")
        .with(body: '{"name":"Patched"}', headers: { "content-type" => "application/json" })
        .to_return(status: 200, body: '{"id":1,"name":"Patched"}')

      response = client.patch("/users/1", json: { name: "Patched" })

      expect(response.status).to eq(200)
    end
  end

  describe "DELETE requests" do
    it "sends a DELETE request" do
      stub_request(:delete, "https://api.example.com/users/1")
        .to_return(status: 204, body: "")

      response = client.delete("/users/1")

      expect(response.status).to eq(204)
      expect(response.ok?).to be(true)
    end
  end

  describe "error handling" do
    it "returns non-ok response for 4xx status" do
      stub_request(:get, "https://api.example.com/missing")
        .to_return(status: 404, body: '{"error":"not found"}')

      response = client.get("/missing")

      expect(response.status).to eq(404)
      expect(response.ok?).to be(false)
    end

    it "returns non-ok response for 5xx status" do
      stub_request(:get, "https://api.example.com/error")
        .to_return(status: 500, body: '{"error":"server error"}')

      response = client.get("/error")

      expect(response.status).to eq(500)
      expect(response.ok?).to be(false)
    end

    it "raises JSON::ParserError for invalid JSON" do
      stub_request(:get, "https://api.example.com/text")
        .to_return(status: 200, body: "not json")

      response = client.get("/text")

      expect { response.json }.to raise_error(JSON::ParserError)
    end
  end

  describe "retries" do
    it "retries on connection error and succeeds" do
      client_with_retries = described_class.new(base_url: base_url, retries: 2, retry_delay: 0)

      stub_request(:get, "https://api.example.com/flaky")
        .to_raise(Errno::ECONNREFUSED)
        .then
        .to_return(status: 200, body: "ok")

      response = client_with_retries.get("/flaky")

      expect(response.status).to eq(200)
    end

    it "raises after exhausting retries" do
      client_with_retries = described_class.new(base_url: base_url, retries: 1, retry_delay: 0)

      stub_request(:get, "https://api.example.com/down")
        .to_raise(Errno::ECONNREFUSED)

      expect { client_with_retries.get("/down") }.to raise_error(Errno::ECONNREFUSED)
    end
  end

  describe "HEAD requests" do
    it "performs a HEAD request and returns a response" do
      stub_request(:head, "https://api.example.com/health")
        .to_return(status: 200, body: "", headers: { "x-request-id" => "abc123" })

      response = client.head("/health")

      expect(response.status).to eq(200)
      expect(response.ok?).to be(true)
      expect(response.headers["x-request-id"]).to eq("abc123")
    end
  end

  describe "per-request timeout" do
    it "uses the per-request timeout when provided" do
      stub_request(:get, "https://api.example.com/slow")
        .to_return(status: 200, body: "ok")

      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return("200")
      allow(raw_response).to receive(:body).and_return("ok")
      allow(raw_response).to receive(:each_header)
      allow(http_double).to receive(:request).and_return(raw_response)

      client.get("/slow", timeout: 5)

      expect(http_double).to have_received(:open_timeout=).with(5)
      expect(http_double).to have_received(:read_timeout=).with(5)
    end
  end

  describe "exponential backoff" do
    it "uses exponential backoff delays when retry_backoff is :exponential" do
      client_exp = described_class.new(
        base_url: base_url, retries: 3, retry_delay: 1, retry_backoff: :exponential
      )

      stub_request(:get, "https://api.example.com/flaky")
        .to_raise(Errno::ECONNREFUSED)
        .then.to_raise(Errno::ECONNREFUSED)
        .then.to_raise(Errno::ECONNREFUSED)
        .then.to_return(status: 200, body: "ok")

      allow(client_exp).to receive(:sleep)

      response = client_exp.get("/flaky")

      expect(response.status).to eq(200)
      expect(client_exp).to have_received(:sleep).with(1).ordered
      expect(client_exp).to have_received(:sleep).with(2).ordered
      expect(client_exp).to have_received(:sleep).with(4).ordered
    end
  end

  describe "request_count" do
    it "starts at zero" do
      expect(client.request_count).to eq(0)
    end

    it "increments with each request" do
      stub_request(:get, "https://api.example.com/one")
        .to_return(status: 200, body: "ok")
      stub_request(:post, "https://api.example.com/two")
        .to_return(status: 201, body: "created")

      client.get("/one")
      client.post("/two", body: "data")

      expect(client.request_count).to eq(2)
    end
  end

  describe "interceptors" do
    it "calls interceptor before and after request" do
      calls = []

      client.use do |context|
        calls << (context[:response] ? :after : :before)
      end

      stub_request(:get, "https://api.example.com/test")
        .to_return(status: 200, body: "ok")

      client.get("/test")

      expect(calls).to eq(%i[before after])
    end

    it "provides request and response in context" do
      captured = nil

      client.use do |context|
        captured = context if context[:response]
      end

      stub_request(:get, "https://api.example.com/info")
        .to_return(status: 200, body: '{"ok":true}')

      client.get("/info")

      expect(captured[:request][:method]).to eq("GET")
      expect(captured[:response].status).to eq(200)
    end
  end

  describe "retry on status codes" do
    it "retries on specified HTTP status codes" do
      client_retry = described_class.new(
        base_url: base_url, retries: 2, retry_delay: 0, retry_on_status: [429, 503]
      )

      stub_request(:get, "https://api.example.com/rate-limited")
        .to_return(status: 429, body: "too many requests")
        .then
        .to_return(status: 200, body: "ok")

      response = client_retry.get("/rate-limited")

      expect(response.status).to eq(200)
    end

    it "returns the last response when retries exhausted on status" do
      client_retry = described_class.new(
        base_url: base_url, retries: 1, retry_delay: 0, retry_on_status: [503]
      )

      stub_request(:get, "https://api.example.com/down")
        .to_return(status: 503, body: "unavailable")

      response = client_retry.get("/down")

      expect(response.status).to eq(503)
    end
  end

  describe "form body" do
    it "sends a form-urlencoded body" do
      stub_request(:post, "https://api.example.com/login")
        .with(
          body: "username=alice&password=secret",
          headers: { "content-type" => "application/x-www-form-urlencoded" }
        )
        .to_return(status: 200, body: '{"token":"abc"}')

      response = client.post("/login", form: { username: "alice", password: "secret" })

      expect(response.status).to eq(200)
    end
  end

  describe "bearer_token" do
    it "sets the authorization header for subsequent requests" do
      client.bearer_token("mytoken123")

      stub_request(:get, "https://api.example.com/me")
        .with(headers: { "authorization" => "Bearer mytoken123" })
        .to_return(status: 200, body: '{"id":1}')

      response = client.get("/me")

      expect(response.status).to eq(200)
    end

    it "returns self for chaining" do
      expect(client.bearer_token("token")).to be(client)
    end
  end

  describe "basic_auth" do
    it "sets the authorization header with base64 credentials" do
      client.basic_auth("user", "pass")

      stub_request(:get, "https://api.example.com/me")
        .with(headers: { "authorization" => "Basic dXNlcjpwYXNz" })
        .to_return(status: 200, body: '{"id":1}')

      response = client.get("/me")

      expect(response.status).to eq(200)
    end

    it "returns self for chaining" do
      expect(client.basic_auth("u", "p")).to be(client)
    end
  end
end
