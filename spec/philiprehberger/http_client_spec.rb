# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "tempfile"

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
      expect(Philiprehberger::HttpClient::VERSION).not_to be_nil
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

    it "raises NetworkError after exhausting retries on connection errors" do
      client_with_retries = described_class.new(base_url: base_url, retries: 1, retry_delay: 0)

      stub_request(:get, "https://api.example.com/down")
        .to_raise(Errno::ECONNREFUSED)

      expect { client_with_retries.get("/down") }.to raise_error(Philiprehberger::HttpClient::NetworkError)
    end

    it "raises TimeoutError after exhausting retries on timeout errors" do
      client_with_retries = described_class.new(base_url: base_url, retries: 1, retry_delay: 0)

      stub_request(:get, "https://api.example.com/slow")
        .to_raise(Net::ReadTimeout)

      expect { client_with_retries.get("/slow") }.to raise_error(Philiprehberger::HttpClient::TimeoutError)
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
      allow(http_double).to receive(:write_timeout=)

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

  # === New feature tests ===

  describe "custom error hierarchy" do
    it "defines Error as base class" do
      expect(Philiprehberger::HttpClient::Error.superclass).to eq(StandardError)
    end

    it "defines TimeoutError inheriting from Error" do
      expect(Philiprehberger::HttpClient::TimeoutError.superclass).to eq(Philiprehberger::HttpClient::Error)
    end

    it "defines NetworkError inheriting from Error" do
      expect(Philiprehberger::HttpClient::NetworkError.superclass).to eq(Philiprehberger::HttpClient::Error)
    end

    it "defines HttpError inheriting from Error" do
      expect(Philiprehberger::HttpClient::HttpError.superclass).to eq(Philiprehberger::HttpClient::Error)
    end

    it "wraps Net::OpenTimeout as TimeoutError" do
      stub_request(:get, "https://api.example.com/timeout")
        .to_raise(Net::OpenTimeout)

      expect { client.get("/timeout") }.to raise_error(Philiprehberger::HttpClient::TimeoutError)
    end

    it "wraps Net::ReadTimeout as TimeoutError" do
      stub_request(:get, "https://api.example.com/timeout")
        .to_raise(Net::ReadTimeout.new("read timeout"))

      expect { client.get("/timeout") }.to raise_error(Philiprehberger::HttpClient::TimeoutError)
    end

    it "wraps Errno::ECONNREFUSED as NetworkError" do
      stub_request(:get, "https://api.example.com/network")
        .to_raise(Errno::ECONNREFUSED)

      expect { client.get("/network") }.to raise_error(Philiprehberger::HttpClient::NetworkError)
    end

    it "wraps Errno::ECONNRESET as NetworkError" do
      stub_request(:get, "https://api.example.com/network")
        .to_raise(Errno::ECONNRESET)

      expect { client.get("/network") }.to raise_error(Philiprehberger::HttpClient::NetworkError)
    end

    it "wraps SocketError as NetworkError" do
      stub_request(:get, "https://api.example.com/network")
        .to_raise(SocketError)

      expect { client.get("/network") }.to raise_error(Philiprehberger::HttpClient::NetworkError)
    end

    it "allows catching all errors with base Error class" do
      stub_request(:get, "https://api.example.com/fail")
        .to_raise(Net::ReadTimeout.new("timeout"))

      expect { client.get("/fail") }.to raise_error(Philiprehberger::HttpClient::Error)
    end

    it "includes response in HttpError" do
      stub_request(:get, "https://api.example.com/bad")
        .to_return(status: 400, body: "bad request")

      error = nil
      begin
        client.get("/bad", expect: [200])
      rescue Philiprehberger::HttpClient::HttpError => e
        error = e
      end

      expect(error).not_to be_nil
      expect(error.response.status).to eq(400)
      expect(error.message).to include("HTTP 400")
    end
  end

  describe "streaming responses" do
    it "yields chunks to the block" do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return("200")
      allow(raw_response).to receive(:each_header)
      allow(raw_response).to receive(:read_body).and_yield("chunk1").and_yield("chunk2")

      allow(http_double).to receive(:request).and_yield(raw_response)

      chunks = []
      response = client.get("/large-file") { |chunk| chunks << chunk }

      expect(chunks).to eq(%w[chunk1 chunk2])
      expect(response.body).to be_nil
      expect(response.streaming?).to be(true)
    end

    it "returns a response with streaming flag" do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return("200")
      allow(raw_response).to receive(:each_header)
      allow(raw_response).to receive(:read_body)

      allow(http_double).to receive(:request).and_yield(raw_response)

      response = client.get("/stream") { |_chunk| nil }

      expect(response.status).to eq(200)
      expect(response.streaming?).to be(true)
    end

    it "captures headers from streaming response" do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return("200")
      allow(raw_response).to receive(:each_header).and_yield("content-type", "text/plain")
      allow(raw_response).to receive(:read_body)

      allow(http_double).to receive(:request).and_yield(raw_response)

      response = client.get("/stream") { |_chunk| nil }

      expect(response.headers["content-type"]).to eq("text/plain")
    end

    it "works with POST streaming" do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return("200")
      allow(raw_response).to receive(:each_header)
      allow(raw_response).to receive(:read_body).and_yield("data")

      allow(http_double).to receive(:request).and_yield(raw_response)

      chunks = []
      response = client.post("/upload", body: "data") { |chunk| chunks << chunk }

      expect(chunks).to eq(["data"])
      expect(response.streaming?).to be(true)
    end

    it "non-streaming responses have streaming? as false" do
      stub_request(:get, "https://api.example.com/normal")
        .to_return(status: 200, body: "ok")

      response = client.get("/normal")

      expect(response.streaming?).to be(false)
    end
  end

  describe "multipart form data" do
    it "sends multipart body with string fields" do
      stub_request(:post, "https://api.example.com/upload")
        .with { |req| req.headers["Content-Type"]&.include?("multipart/form-data") }
        .to_return(status: 200, body: "ok")

      response = client.post("/upload", multipart: { name: "vacation", location: "beach" })

      expect(response.status).to eq(200)
    end

    it "sends multipart body with file objects" do
      file = Tempfile.new(["photo", ".jpg"])
      file.write("file contents")
      file.rewind

      stub = stub_request(:post, "https://api.example.com/upload")
      stub.with do |req|
        req.headers["Content-Type"]&.include?("multipart/form-data") &&
          req.body.include?("file contents") &&
          req.body.include?(".jpg")
      end
      stub.to_return(status: 200, body: '{"id":1}')

      response = client.post("/upload", multipart: { file: file, name: "vacation" })

      expect(response.status).to eq(200)
    ensure
      file.close
      file.unlink
    end

    it "includes boundary in content-type header" do
      stub = stub_request(:post, "https://api.example.com/upload")
      stub.with do |req|
        ct = req.headers["Content-Type"]
        ct&.start_with?("multipart/form-data; boundary=")
      end
      stub.to_return(status: 200, body: "ok")

      client.post("/upload", multipart: { key: "value" })
    end

    it "builds proper multipart structure" do
      body, content_type = Philiprehberger::HttpClient::Multipart.build({ name: "test", age: "25" })

      expect(content_type).to start_with("multipart/form-data; boundary=")
      expect(body).to include("Content-Disposition: form-data; name=\"name\"")
      expect(body).to include("test")
      expect(body).to include("Content-Disposition: form-data; name=\"age\"")
      expect(body).to include("25")
    end

    it "builds file parts with filename and content-type" do
      file = Tempfile.new(["image", ".png"])
      file.write("binary data")
      file.rewind

      body, = Philiprehberger::HttpClient::Multipart.build({ image: file })

      expect(body).to include('filename="')
      expect(body).to include("Content-Type: application/octet-stream")
      expect(body).to include("binary data")
    ensure
      file.close
      file.unlink
    end

    it "rewinds file after reading" do
      file = Tempfile.new(["test", ".txt"])
      file.write("data")
      file.rewind

      Philiprehberger::HttpClient::Multipart.build({ file: file })

      expect(file.pos).to eq(0)
    ensure
      file.close
      file.unlink
    end

    it "works with PUT method" do
      stub_request(:put, "https://api.example.com/resource/1")
        .with { |req| req.headers["Content-Type"]&.include?("multipart/form-data") }
        .to_return(status: 200, body: "ok")

      response = client.put("/resource/1", multipart: { name: "updated" })

      expect(response.status).to eq(200)
    end
  end

  describe "per-phase timeouts" do
    it "sets individual timeout phases from constructor" do
      phase_client = described_class.new(
        base_url: base_url, open_timeout: 5, read_timeout: 30, write_timeout: 10
      )

      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return("200")
      allow(raw_response).to receive(:body).and_return("ok")
      allow(raw_response).to receive(:each_header)
      allow(http_double).to receive(:request).and_return(raw_response)

      phase_client.get("/test")

      expect(http_double).to have_received(:open_timeout=).with(5)
      expect(http_double).to have_received(:read_timeout=).with(30)
      expect(http_double).to have_received(:write_timeout=).with(10)
    end

    it "per-phase timeouts override general timeout" do
      phase_client = described_class.new(
        base_url: base_url, timeout: 60, open_timeout: 5, read_timeout: 15
      )

      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return("200")
      allow(raw_response).to receive(:body).and_return("ok")
      allow(raw_response).to receive(:each_header)
      allow(http_double).to receive(:request).and_return(raw_response)

      phase_client.get("/test")

      expect(http_double).to have_received(:open_timeout=).with(5)
      expect(http_double).to have_received(:read_timeout=).with(15)
      expect(http_double).to have_received(:write_timeout=).with(60)
    end

    it "per-request phase timeouts override constructor timeouts" do
      phase_client = described_class.new(
        base_url: base_url, open_timeout: 5, read_timeout: 30
      )

      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return("200")
      allow(raw_response).to receive(:body).and_return("ok")
      allow(raw_response).to receive(:each_header)
      allow(http_double).to receive(:request).and_return(raw_response)

      phase_client.get("/test", open_timeout: 2, read_timeout: 10)

      expect(http_double).to have_received(:open_timeout=).with(2)
      expect(http_double).to have_received(:read_timeout=).with(10)
    end

    it "falls back to general timeout when no phase timeout set" do
      phase_client = described_class.new(base_url: base_url, timeout: 45)

      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return("200")
      allow(raw_response).to receive(:body).and_return("ok")
      allow(raw_response).to receive(:each_header)
      allow(http_double).to receive(:request).and_return(raw_response)

      phase_client.get("/test")

      expect(http_double).to have_received(:open_timeout=).with(45)
      expect(http_double).to have_received(:read_timeout=).with(45)
      expect(http_double).to have_received(:write_timeout=).with(45)
    end

    it "supports per-request phase timeouts on POST" do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return("201")
      allow(raw_response).to receive(:body).and_return("ok")
      allow(raw_response).to receive(:each_header)
      allow(http_double).to receive(:request).and_return(raw_response)

      client.post("/data", json: { a: 1 }, write_timeout: 60, read_timeout: 120)

      expect(http_double).to have_received(:write_timeout=).with(60)
      expect(http_double).to have_received(:read_timeout=).with(120)
    end

    it "supports per-request phase timeouts on DELETE" do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return("204")
      allow(raw_response).to receive(:body).and_return("")
      allow(raw_response).to receive(:each_header)
      allow(http_double).to receive(:request).and_return(raw_response)

      client.delete("/resource/1", open_timeout: 3)

      expect(http_double).to have_received(:open_timeout=).with(3)
    end
  end

  describe "response validation (expect:)" do
    it "does not raise when status matches expected" do
      stub_request(:get, "https://api.example.com/ok")
        .to_return(status: 200, body: "ok")

      response = client.get("/ok", expect: [200])

      expect(response.status).to eq(200)
    end

    it "accepts multiple expected status codes" do
      stub_request(:get, "https://api.example.com/created")
        .to_return(status: 201, body: "created")

      response = client.get("/created", expect: [200, 201])

      expect(response.status).to eq(201)
    end

    it "raises HttpError when status not in expected list" do
      stub_request(:get, "https://api.example.com/fail")
        .to_return(status: 404, body: "not found")

      expect do
        client.get("/fail", expect: [200])
      end.to raise_error(Philiprehberger::HttpClient::HttpError) do |e|
        expect(e.response.status).to eq(404)
        expect(e.message).to include("HTTP 404")
      end
    end

    it "raises HttpError for server errors when expecting success" do
      stub_request(:post, "https://api.example.com/create")
        .to_return(status: 500, body: "internal error")

      expect do
        client.post("/create", json: { a: 1 }, expect: [201])
      end.to raise_error(Philiprehberger::HttpClient::HttpError) do |e|
        expect(e.response.status).to eq(500)
      end
    end

    it "works with PUT requests" do
      stub_request(:put, "https://api.example.com/resource/1")
        .to_return(status: 200, body: "ok")

      response = client.put("/resource/1", json: { a: 1 }, expect: [200])

      expect(response.status).to eq(200)
    end

    it "works with PATCH requests" do
      stub_request(:patch, "https://api.example.com/resource/1")
        .to_return(status: 422, body: "unprocessable")

      expect do
        client.patch("/resource/1", json: { a: 1 }, expect: [200])
      end.to raise_error(Philiprehberger::HttpClient::HttpError)
    end

    it "works with DELETE requests" do
      stub_request(:delete, "https://api.example.com/resource/1")
        .to_return(status: 204, body: "")

      response = client.delete("/resource/1", expect: [204])

      expect(response.status).to eq(204)
    end

    it "works with HEAD requests" do
      stub_request(:head, "https://api.example.com/health")
        .to_return(status: 503, body: "")

      expect do
        client.head("/health", expect: [200])
      end.to raise_error(Philiprehberger::HttpClient::HttpError)
    end

    it "does not validate when expect is nil" do
      stub_request(:get, "https://api.example.com/fail")
        .to_return(status: 500, body: "error")

      response = client.get("/fail")

      expect(response.status).to eq(500)
    end

    it "HttpError includes truncated body in message" do
      long_body = "x" * 300
      stub_request(:get, "https://api.example.com/long")
        .to_return(status: 400, body: long_body)

      expect do
        client.get("/long", expect: [200])
      end.to raise_error(Philiprehberger::HttpClient::HttpError) do |e|
        expect(e.message.length).to be < 250
      end
    end

    it "interceptors run before validation" do
      interceptor_called = false

      client.use do |context|
        interceptor_called = true if context[:response]
      end

      stub_request(:get, "https://api.example.com/fail")
        .to_return(status: 400, body: "bad")

      expect do
        client.get("/fail", expect: [200])
      end.to raise_error(Philiprehberger::HttpClient::HttpError)

      expect(interceptor_called).to be(true)
    end
  end
end
