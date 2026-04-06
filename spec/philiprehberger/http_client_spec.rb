# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tempfile'

RSpec.describe Philiprehberger::HttpClient do
  let(:base_url) { 'https://api.example.com' }
  let(:client) { described_class.new(base_url: base_url) }

  describe '.new' do
    it 'returns a Client instance' do
      expect(client).to be_a(Philiprehberger::HttpClient::Client)
    end
  end

  describe 'VERSION' do
    it 'has a version number' do
      expect(Philiprehberger::HttpClient::VERSION).not_to be_nil
    end
  end

  describe 'GET requests' do
    it 'performs a simple GET request' do
      stub_request(:get, 'https://api.example.com/users')
        .to_return(status: 200, body: '[{"id":1}]', headers: { 'content-type' => 'application/json' })

      response = client.get('/users')

      expect(response.status).to eq(200)
      expect(response.ok?).to be(true)
      expect(response.json).to eq([{ 'id' => 1 }])
    end

    it 'sends query parameters' do
      stub_request(:get, 'https://api.example.com/users?page=2&per_page=10')
        .to_return(status: 200, body: '[]')

      response = client.get('/users', params: { page: 2, per_page: 10 })

      expect(response.status).to eq(200)
    end

    it 'includes default headers' do
      client_with_headers = described_class.new(
        base_url: base_url,
        headers: { 'Authorization' => 'Bearer token123' }
      )

      stub_request(:get, 'https://api.example.com/me')
        .with(headers: { 'Authorization' => 'Bearer token123' })
        .to_return(status: 200, body: '{}')

      response = client_with_headers.get('/me')

      expect(response.status).to eq(200)
    end
  end

  describe 'POST requests' do
    it 'sends a JSON body' do
      stub_request(:post, 'https://api.example.com/users')
        .with(
          body: '{"name":"Alice"}',
          headers: { 'content-type' => 'application/json' }
        )
        .to_return(status: 201, body: '{"id":1,"name":"Alice"}')

      response = client.post('/users', json: { name: 'Alice' })

      expect(response.status).to eq(201)
      expect(response.json).to eq({ 'id' => 1, 'name' => 'Alice' })
    end

    it 'sends a raw body' do
      stub_request(:post, 'https://api.example.com/data')
        .with(body: 'raw content')
        .to_return(status: 200, body: 'ok')

      response = client.post('/data', body: 'raw content')

      expect(response.status).to eq(200)
      expect(response.body).to eq('ok')
    end
  end

  describe 'PUT requests' do
    it 'sends a JSON PUT request' do
      stub_request(:put, 'https://api.example.com/users/1')
        .with(body: '{"name":"Updated"}', headers: { 'content-type' => 'application/json' })
        .to_return(status: 200, body: '{"id":1,"name":"Updated"}')

      response = client.put('/users/1', json: { name: 'Updated' })

      expect(response.status).to eq(200)
    end
  end

  describe 'PATCH requests' do
    it 'sends a JSON PATCH request' do
      stub_request(:patch, 'https://api.example.com/users/1')
        .with(body: '{"name":"Patched"}', headers: { 'content-type' => 'application/json' })
        .to_return(status: 200, body: '{"id":1,"name":"Patched"}')

      response = client.patch('/users/1', json: { name: 'Patched' })

      expect(response.status).to eq(200)
    end
  end

  describe 'DELETE requests' do
    it 'sends a DELETE request' do
      stub_request(:delete, 'https://api.example.com/users/1')
        .to_return(status: 204, body: '')

      response = client.delete('/users/1')

      expect(response.status).to eq(204)
      expect(response.ok?).to be(true)
    end
  end

  describe 'error handling' do
    it 'returns non-ok response for 4xx status' do
      stub_request(:get, 'https://api.example.com/missing')
        .to_return(status: 404, body: '{"error":"not found"}')

      response = client.get('/missing')

      expect(response.status).to eq(404)
      expect(response.ok?).to be(false)
    end

    it 'returns non-ok response for 5xx status' do
      stub_request(:get, 'https://api.example.com/error')
        .to_return(status: 500, body: '{"error":"server error"}')

      response = client.get('/error')

      expect(response.status).to eq(500)
      expect(response.ok?).to be(false)
    end

    it 'raises JSON::ParserError for invalid JSON' do
      stub_request(:get, 'https://api.example.com/text')
        .to_return(status: 200, body: 'not json')

      response = client.get('/text')

      expect { response.json }.to raise_error(JSON::ParserError)
    end
  end

  describe 'retries' do
    it 'retries on connection error and succeeds' do
      client_with_retries = described_class.new(base_url: base_url, retries: 2, retry_delay: 0)

      stub_request(:get, 'https://api.example.com/flaky')
        .to_raise(Errno::ECONNREFUSED)
        .then
        .to_return(status: 200, body: 'ok')

      response = client_with_retries.get('/flaky')

      expect(response.status).to eq(200)
    end

    it 'raises NetworkError after exhausting retries on connection errors' do
      client_with_retries = described_class.new(base_url: base_url, retries: 1, retry_delay: 0)

      stub_request(:get, 'https://api.example.com/down')
        .to_raise(Errno::ECONNREFUSED)

      expect { client_with_retries.get('/down') }.to raise_error(Philiprehberger::HttpClient::NetworkError)
    end

    it 'raises TimeoutError after exhausting retries on timeout errors' do
      client_with_retries = described_class.new(base_url: base_url, retries: 1, retry_delay: 0)

      stub_request(:get, 'https://api.example.com/slow')
        .to_raise(Net::ReadTimeout)

      expect { client_with_retries.get('/slow') }.to raise_error(Philiprehberger::HttpClient::TimeoutError)
    end
  end

  describe 'HEAD requests' do
    it 'performs a HEAD request and returns a response' do
      stub_request(:head, 'https://api.example.com/health')
        .to_return(status: 200, body: '', headers: { 'x-request-id' => 'abc123' })

      response = client.head('/health')

      expect(response.status).to eq(200)
      expect(response.ok?).to be(true)
      expect(response.headers['x-request-id']).to eq('abc123')
    end
  end

  describe 'per-request timeout' do
    it 'uses the per-request timeout when provided' do
      stub_request(:get, 'https://api.example.com/slow')
        .to_return(status: 200, body: 'ok')

      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return('200')
      allow(raw_response).to receive(:body).and_return('ok')
      allow(raw_response).to receive(:each_header)
      allow(http_double).to receive(:request).and_return(raw_response)

      client.get('/slow', timeout: 5)

      expect(http_double).to have_received(:open_timeout=).with(5)
      expect(http_double).to have_received(:read_timeout=).with(5)
    end
  end

  describe 'exponential backoff' do
    it 'uses exponential backoff delays when retry_backoff is :exponential' do
      client_exp = described_class.new(
        base_url: base_url, retries: 3, retry_delay: 1, retry_backoff: :exponential
      )

      stub_request(:get, 'https://api.example.com/flaky')
        .to_raise(Errno::ECONNREFUSED)
        .then.to_raise(Errno::ECONNREFUSED)
        .then.to_raise(Errno::ECONNREFUSED)
        .then.to_return(status: 200, body: 'ok')

      allow(client_exp).to receive(:sleep)

      response = client_exp.get('/flaky')

      expect(response.status).to eq(200)
      expect(client_exp).to have_received(:sleep).with(1).ordered
      expect(client_exp).to have_received(:sleep).with(2).ordered
      expect(client_exp).to have_received(:sleep).with(4).ordered
    end
  end

  describe 'request_count' do
    it 'starts at zero' do
      expect(client.request_count).to eq(0)
    end

    it 'increments with each request' do
      stub_request(:get, 'https://api.example.com/one')
        .to_return(status: 200, body: 'ok')
      stub_request(:post, 'https://api.example.com/two')
        .to_return(status: 201, body: 'created')

      client.get('/one')
      client.post('/two', body: 'data')

      expect(client.request_count).to eq(2)
    end
  end

  describe 'interceptors' do
    it 'calls interceptor before and after request' do
      calls = []

      client.use do |context|
        calls << (context[:response] ? :after : :before)
      end

      stub_request(:get, 'https://api.example.com/test')
        .to_return(status: 200, body: 'ok')

      client.get('/test')

      expect(calls).to eq(%i[before after])
    end

    it 'provides request and response in context' do
      captured = nil

      client.use do |context|
        captured = context if context[:response]
      end

      stub_request(:get, 'https://api.example.com/info')
        .to_return(status: 200, body: '{"ok":true}')

      client.get('/info')

      expect(captured[:request][:method]).to eq('GET')
      expect(captured[:response].status).to eq(200)
    end
  end

  describe 'retry on status codes' do
    it 'retries on specified HTTP status codes' do
      client_retry = described_class.new(
        base_url: base_url, retries: 2, retry_delay: 0, retry_on_status: [429, 503]
      )

      stub_request(:get, 'https://api.example.com/rate-limited')
        .to_return(status: 429, body: 'too many requests')
        .then
        .to_return(status: 200, body: 'ok')

      response = client_retry.get('/rate-limited')

      expect(response.status).to eq(200)
    end

    it 'returns the last response when retries exhausted on status' do
      client_retry = described_class.new(
        base_url: base_url, retries: 1, retry_delay: 0, retry_on_status: [503]
      )

      stub_request(:get, 'https://api.example.com/down')
        .to_return(status: 503, body: 'unavailable')

      response = client_retry.get('/down')

      expect(response.status).to eq(503)
    end
  end

  describe 'form body' do
    it 'sends a form-urlencoded body' do
      stub_request(:post, 'https://api.example.com/login')
        .with(
          body: 'username=alice&password=secret',
          headers: { 'content-type' => 'application/x-www-form-urlencoded' }
        )
        .to_return(status: 200, body: '{"token":"abc"}')

      response = client.post('/login', form: { username: 'alice', password: 'secret' })

      expect(response.status).to eq(200)
    end
  end

  describe 'bearer_token' do
    it 'sets the authorization header for subsequent requests' do
      client.bearer_token('mytoken123')

      stub_request(:get, 'https://api.example.com/me')
        .with(headers: { 'authorization' => 'Bearer mytoken123' })
        .to_return(status: 200, body: '{"id":1}')

      response = client.get('/me')

      expect(response.status).to eq(200)
    end

    it 'returns self for chaining' do
      expect(client.bearer_token('token')).to be(client)
    end
  end

  describe 'basic_auth' do
    it 'sets the authorization header with base64 credentials' do
      client.basic_auth('user', 'pass')

      stub_request(:get, 'https://api.example.com/me')
        .with(headers: { 'authorization' => 'Basic dXNlcjpwYXNz' })
        .to_return(status: 200, body: '{"id":1}')

      response = client.get('/me')

      expect(response.status).to eq(200)
    end

    it 'returns self for chaining' do
      expect(client.basic_auth('u', 'p')).to be(client)
    end
  end

  # === New feature tests ===

  describe 'custom error hierarchy' do
    it 'defines Error as base class' do
      expect(Philiprehberger::HttpClient::Error.superclass).to eq(StandardError)
    end

    it 'defines TimeoutError inheriting from Error' do
      expect(Philiprehberger::HttpClient::TimeoutError.superclass).to eq(Philiprehberger::HttpClient::Error)
    end

    it 'defines NetworkError inheriting from Error' do
      expect(Philiprehberger::HttpClient::NetworkError.superclass).to eq(Philiprehberger::HttpClient::Error)
    end

    it 'defines HttpError inheriting from Error' do
      expect(Philiprehberger::HttpClient::HttpError.superclass).to eq(Philiprehberger::HttpClient::Error)
    end

    it 'wraps Net::OpenTimeout as TimeoutError' do
      stub_request(:get, 'https://api.example.com/timeout')
        .to_raise(Net::OpenTimeout)

      expect { client.get('/timeout') }.to raise_error(Philiprehberger::HttpClient::TimeoutError)
    end

    it 'wraps Net::ReadTimeout as TimeoutError' do
      stub_request(:get, 'https://api.example.com/timeout')
        .to_raise(Net::ReadTimeout.new('read timeout'))

      expect { client.get('/timeout') }.to raise_error(Philiprehberger::HttpClient::TimeoutError)
    end

    it 'wraps Errno::ECONNREFUSED as NetworkError' do
      stub_request(:get, 'https://api.example.com/network')
        .to_raise(Errno::ECONNREFUSED)

      expect { client.get('/network') }.to raise_error(Philiprehberger::HttpClient::NetworkError)
    end

    it 'wraps Errno::ECONNRESET as NetworkError' do
      stub_request(:get, 'https://api.example.com/network')
        .to_raise(Errno::ECONNRESET)

      expect { client.get('/network') }.to raise_error(Philiprehberger::HttpClient::NetworkError)
    end

    it 'wraps SocketError as NetworkError' do
      stub_request(:get, 'https://api.example.com/network')
        .to_raise(SocketError)

      expect { client.get('/network') }.to raise_error(Philiprehberger::HttpClient::NetworkError)
    end

    it 'allows catching all errors with base Error class' do
      stub_request(:get, 'https://api.example.com/fail')
        .to_raise(Net::ReadTimeout.new('timeout'))

      expect { client.get('/fail') }.to raise_error(Philiprehberger::HttpClient::Error)
    end

    it 'includes response in HttpError' do
      stub_request(:get, 'https://api.example.com/bad')
        .to_return(status: 400, body: 'bad request')

      error = nil
      begin
        client.get('/bad', expect: [200])
      rescue Philiprehberger::HttpClient::HttpError => e
        error = e
      end

      expect(error).not_to be_nil
      expect(error.response.status).to eq(400)
      expect(error.message).to include('HTTP 400')
    end
  end

  describe 'streaming responses' do
    it 'yields chunks to the block' do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return('200')
      allow(raw_response).to receive(:each_header)
      allow(raw_response).to receive(:read_body).and_yield('chunk1').and_yield('chunk2')

      allow(http_double).to receive(:request).and_yield(raw_response)

      chunks = []
      response = client.get('/large-file') { |chunk| chunks << chunk }

      expect(chunks).to eq(%w[chunk1 chunk2])
      expect(response.body).to be_nil
      expect(response.streaming?).to be(true)
    end

    it 'returns a response with streaming flag' do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return('200')
      allow(raw_response).to receive(:each_header)
      allow(raw_response).to receive(:read_body)

      allow(http_double).to receive(:request).and_yield(raw_response)

      response = client.get('/stream') { |_chunk| nil }

      expect(response.status).to eq(200)
      expect(response.streaming?).to be(true)
    end

    it 'captures headers from streaming response' do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return('200')
      allow(raw_response).to receive(:each_header).and_yield('content-type', 'text/plain')
      allow(raw_response).to receive(:read_body)

      allow(http_double).to receive(:request).and_yield(raw_response)

      response = client.get('/stream') { |_chunk| nil }

      expect(response.headers['content-type']).to eq('text/plain')
    end

    it 'works with POST streaming' do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return('200')
      allow(raw_response).to receive(:each_header)
      allow(raw_response).to receive(:read_body).and_yield('data')

      allow(http_double).to receive(:request).and_yield(raw_response)

      chunks = []
      response = client.post('/upload', body: 'data') { |chunk| chunks << chunk }

      expect(chunks).to eq(['data'])
      expect(response.streaming?).to be(true)
    end

    it 'non-streaming responses have streaming? as false' do
      stub_request(:get, 'https://api.example.com/normal')
        .to_return(status: 200, body: 'ok')

      response = client.get('/normal')

      expect(response.streaming?).to be(false)
    end
  end

  describe 'multipart form data' do
    it 'sends multipart body with string fields' do
      stub_request(:post, 'https://api.example.com/upload')
        .with { |req| req.headers['Content-Type']&.include?('multipart/form-data') }
        .to_return(status: 200, body: 'ok')

      response = client.post('/upload', multipart: { name: 'vacation', location: 'beach' })

      expect(response.status).to eq(200)
    end

    it 'sends multipart body with file objects' do
      file = Tempfile.new(['photo', '.jpg'])
      file.write('file contents')
      file.rewind

      stub = stub_request(:post, 'https://api.example.com/upload')
      stub.with do |req|
        req.headers['Content-Type']&.include?('multipart/form-data') &&
          req.body.include?('file contents') &&
          req.body.include?('.jpg')
      end
      stub.to_return(status: 200, body: '{"id":1}')

      response = client.post('/upload', multipart: { file: file, name: 'vacation' })

      expect(response.status).to eq(200)
    ensure
      file.close
      file.unlink
    end

    it 'includes boundary in content-type header' do
      stub = stub_request(:post, 'https://api.example.com/upload')
      stub.with do |req|
        ct = req.headers['Content-Type']
        ct&.start_with?('multipart/form-data; boundary=')
      end
      stub.to_return(status: 200, body: 'ok')

      client.post('/upload', multipart: { key: 'value' })
    end

    it 'builds proper multipart structure' do
      body, content_type = Philiprehberger::HttpClient::Multipart.build({ name: 'test', age: '25' })

      expect(content_type).to start_with('multipart/form-data; boundary=')
      expect(body).to include('Content-Disposition: form-data; name="name"')
      expect(body).to include('test')
      expect(body).to include('Content-Disposition: form-data; name="age"')
      expect(body).to include('25')
    end

    it 'builds file parts with filename and content-type' do
      file = Tempfile.new(['image', '.png'])
      file.write('binary data')
      file.rewind

      body, = Philiprehberger::HttpClient::Multipart.build({ image: file })

      expect(body).to include('filename="')
      expect(body).to include('Content-Type: application/octet-stream')
      expect(body).to include('binary data')
    ensure
      file.close
      file.unlink
    end

    it 'rewinds file after reading' do
      file = Tempfile.new(['test', '.txt'])
      file.write('data')
      file.rewind

      Philiprehberger::HttpClient::Multipart.build({ file: file })

      expect(file.pos).to eq(0)
    ensure
      file.close
      file.unlink
    end

    it 'works with PUT method' do
      stub_request(:put, 'https://api.example.com/resource/1')
        .with { |req| req.headers['Content-Type']&.include?('multipart/form-data') }
        .to_return(status: 200, body: 'ok')

      response = client.put('/resource/1', multipart: { name: 'updated' })

      expect(response.status).to eq(200)
    end
  end

  describe 'per-phase timeouts' do
    it 'sets individual timeout phases from constructor' do
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
      allow(raw_response).to receive(:code).and_return('200')
      allow(raw_response).to receive(:body).and_return('ok')
      allow(raw_response).to receive(:each_header)
      allow(http_double).to receive(:request).and_return(raw_response)

      phase_client.get('/test')

      expect(http_double).to have_received(:open_timeout=).with(5)
      expect(http_double).to have_received(:read_timeout=).with(30)
      expect(http_double).to have_received(:write_timeout=).with(10)
    end

    it 'per-phase timeouts override general timeout' do
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
      allow(raw_response).to receive(:code).and_return('200')
      allow(raw_response).to receive(:body).and_return('ok')
      allow(raw_response).to receive(:each_header)
      allow(http_double).to receive(:request).and_return(raw_response)

      phase_client.get('/test')

      expect(http_double).to have_received(:open_timeout=).with(5)
      expect(http_double).to have_received(:read_timeout=).with(15)
      expect(http_double).to have_received(:write_timeout=).with(60)
    end

    it 'per-request phase timeouts override constructor timeouts' do
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
      allow(raw_response).to receive(:code).and_return('200')
      allow(raw_response).to receive(:body).and_return('ok')
      allow(raw_response).to receive(:each_header)
      allow(http_double).to receive(:request).and_return(raw_response)

      phase_client.get('/test', open_timeout: 2, read_timeout: 10)

      expect(http_double).to have_received(:open_timeout=).with(2)
      expect(http_double).to have_received(:read_timeout=).with(10)
    end

    it 'falls back to general timeout when no phase timeout set' do
      phase_client = described_class.new(base_url: base_url, timeout: 45)

      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return('200')
      allow(raw_response).to receive(:body).and_return('ok')
      allow(raw_response).to receive(:each_header)
      allow(http_double).to receive(:request).and_return(raw_response)

      phase_client.get('/test')

      expect(http_double).to have_received(:open_timeout=).with(45)
      expect(http_double).to have_received(:read_timeout=).with(45)
      expect(http_double).to have_received(:write_timeout=).with(45)
    end

    it 'supports per-request phase timeouts on POST' do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return('201')
      allow(raw_response).to receive(:body).and_return('ok')
      allow(raw_response).to receive(:each_header)
      allow(http_double).to receive(:request).and_return(raw_response)

      client.post('/data', json: { a: 1 }, write_timeout: 60, read_timeout: 120)

      expect(http_double).to have_received(:write_timeout=).with(60)
      expect(http_double).to have_received(:read_timeout=).with(120)
    end

    it 'supports per-request phase timeouts on DELETE' do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return('204')
      allow(raw_response).to receive(:body).and_return('')
      allow(raw_response).to receive(:each_header)
      allow(http_double).to receive(:request).and_return(raw_response)

      client.delete('/resource/1', open_timeout: 3)

      expect(http_double).to have_received(:open_timeout=).with(3)
    end
  end

  describe 'response validation (expect:)' do
    it 'does not raise when status matches expected' do
      stub_request(:get, 'https://api.example.com/ok')
        .to_return(status: 200, body: 'ok')

      response = client.get('/ok', expect: [200])

      expect(response.status).to eq(200)
    end

    it 'accepts multiple expected status codes' do
      stub_request(:get, 'https://api.example.com/created')
        .to_return(status: 201, body: 'created')

      response = client.get('/created', expect: [200, 201])

      expect(response.status).to eq(201)
    end

    it 'raises HttpError when status not in expected list' do
      stub_request(:get, 'https://api.example.com/fail')
        .to_return(status: 404, body: 'not found')

      error = nil
      begin
        client.get('/fail', expect: [200])
      rescue Philiprehberger::HttpClient::HttpError => e
        error = e
      end
      expect(error).not_to be_nil
      expect(error.response.status).to eq(404)
      expect(error.message).to include('HTTP 404')
    end

    it 'raises HttpError for server errors when expecting success' do
      stub_request(:post, 'https://api.example.com/create')
        .to_return(status: 500, body: 'internal error')

      error = nil
      begin
        client.post('/create', json: { a: 1 }, expect: [201])
      rescue Philiprehberger::HttpClient::HttpError => e
        error = e
      end
      expect(error).not_to be_nil
      expect(error.response.status).to eq(500)
    end

    it 'works with PUT requests' do
      stub_request(:put, 'https://api.example.com/resource/1')
        .to_return(status: 200, body: 'ok')

      response = client.put('/resource/1', json: { a: 1 }, expect: [200])

      expect(response.status).to eq(200)
    end

    it 'works with PATCH requests' do
      stub_request(:patch, 'https://api.example.com/resource/1')
        .to_return(status: 422, body: 'unprocessable')

      expect do
        client.patch('/resource/1', json: { a: 1 }, expect: [200])
      end.to raise_error(Philiprehberger::HttpClient::HttpError)
    end

    it 'works with DELETE requests' do
      stub_request(:delete, 'https://api.example.com/resource/1')
        .to_return(status: 204, body: '')

      response = client.delete('/resource/1', expect: [204])

      expect(response.status).to eq(204)
    end

    it 'works with HEAD requests' do
      stub_request(:head, 'https://api.example.com/health')
        .to_return(status: 503, body: '')

      expect do
        client.head('/health', expect: [200])
      end.to raise_error(Philiprehberger::HttpClient::HttpError)
    end

    it 'does not validate when expect is nil' do
      stub_request(:get, 'https://api.example.com/fail')
        .to_return(status: 500, body: 'error')

      response = client.get('/fail')

      expect(response.status).to eq(500)
    end

    it 'HttpError includes truncated body in message' do
      long_body = 'x' * 300
      stub_request(:get, 'https://api.example.com/long')
        .to_return(status: 400, body: long_body)

      error = nil
      begin
        client.get('/long', expect: [200])
      rescue Philiprehberger::HttpClient::HttpError => e
        error = e
      end
      expect(error).not_to be_nil
      expect(error.message.length).to be < 250
    end

    it 'interceptors run before validation' do
      interceptor_called = false

      client.use do |context|
        interceptor_called = true if context[:response]
      end

      stub_request(:get, 'https://api.example.com/fail')
        .to_return(status: 400, body: 'bad')

      expect do
        client.get('/fail', expect: [200])
      end.to raise_error(Philiprehberger::HttpClient::HttpError)

      expect(interceptor_called).to be(true)
    end
  end

  # === Expanded coverage: edge cases and error paths ===

  describe 'Response#ok? edge cases' do
    it 'returns false for status 199' do
      stub_request(:get, 'https://api.example.com/edge')
        .to_return(status: 199, body: '')

      response = client.get('/edge')

      expect(response.ok?).to be(false)
    end

    it 'returns true for status 200' do
      stub_request(:get, 'https://api.example.com/edge')
        .to_return(status: 200, body: '')

      response = client.get('/edge')

      expect(response.ok?).to be(true)
    end

    it 'returns true for status 299' do
      stub_request(:get, 'https://api.example.com/edge')
        .to_return(status: 299, body: '')

      response = client.get('/edge')

      expect(response.ok?).to be(true)
    end

    it 'returns false for status 300' do
      stub_request(:get, 'https://api.example.com/edge')
        .to_return(status: 300, body: '')

      response = client.get('/edge')

      expect(response.ok?).to be(false)
    end
  end

  describe 'Response#json memoization' do
    it 'caches parsed JSON across multiple calls' do
      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 200, body: '{"key":"value"}')

      response = client.get('/data')
      first_call = response.json
      second_call = response.json

      expect(first_call).to equal(second_call)
    end
  end

  describe 'empty response body' do
    it 'returns empty string body for response with no content' do
      stub_request(:get, 'https://api.example.com/empty')
        .to_return(status: 204, body: '')

      response = client.get('/empty')

      expect(response.body).to eq('')
    end

    it 'raises JSON::ParserError when parsing empty body as JSON' do
      stub_request(:get, 'https://api.example.com/empty')
        .to_return(status: 200, body: '')

      response = client.get('/empty')

      expect { response.json }.to raise_error(JSON::ParserError)
    end
  end

  describe 'URL path handling' do
    it 'handles path without leading slash' do
      stub_request(:get, 'https://api.example.com/users')
        .to_return(status: 200, body: 'ok')

      response = client.get('users')

      expect(response.status).to eq(200)
    end

    it 'handles base_url with trailing slash' do
      client_trailing = described_class.new(base_url: 'https://api.example.com/')

      stub_request(:get, 'https://api.example.com/users')
        .to_return(status: 200, body: 'ok')

      response = client_trailing.get('/users')

      expect(response.status).to eq(200)
    end
  end

  describe 'multiple interceptors' do
    it 'calls all registered interceptors in order' do
      call_order = []

      client.use { |_ctx| call_order << :first }
      client.use { |_ctx| call_order << :second }

      stub_request(:get, 'https://api.example.com/test')
        .to_return(status: 200, body: 'ok')

      client.get('/test')

      expect(call_order).to eq(%i[first second first second])
    end
  end

  describe 'use returns self' do
    it 'allows chaining interceptors' do
      result = client.use { |_ctx| nil }

      expect(result).to be(client)
    end
  end

  describe 'multipart with StringIO' do
    it 'handles StringIO objects that respond to read but not path' do
      io = StringIO.new('io content')

      body, content_type = Philiprehberger::HttpClient::Multipart.build({ file: io })

      expect(content_type).to start_with('multipart/form-data; boundary=')
      expect(body).to include('io content')
      expect(body).to include('filename="upload"')
    end
  end

  describe 'HEAD with query parameters' do
    it 'sends query parameters on HEAD requests' do
      stub_request(:head, 'https://api.example.com/health?verbose=true')
        .to_return(status: 200, body: '')

      response = client.head('/health', params: { verbose: 'true' })

      expect(response.status).to eq(200)
    end
  end

  describe 'form body on PUT and PATCH' do
    it 'sends form-urlencoded body on PUT' do
      stub_request(:put, 'https://api.example.com/resource/1')
        .with(
          body: 'name=updated',
          headers: { 'content-type' => 'application/x-www-form-urlencoded' }
        )
        .to_return(status: 200, body: 'ok')

      response = client.put('/resource/1', form: { name: 'updated' })

      expect(response.status).to eq(200)
    end

    it 'sends form-urlencoded body on PATCH' do
      stub_request(:patch, 'https://api.example.com/resource/1')
        .with(
          body: 'status=active',
          headers: { 'content-type' => 'application/x-www-form-urlencoded' }
        )
        .to_return(status: 200, body: 'ok')

      response = client.patch('/resource/1', form: { status: 'active' })

      expect(response.status).to eq(200)
    end
  end

  describe 'additional network error types' do
    it 'wraps Errno::ETIMEDOUT as NetworkError' do
      stub_request(:get, 'https://api.example.com/timeout')
        .to_raise(Errno::ETIMEDOUT)

      expect { client.get('/timeout') }.to raise_error(Philiprehberger::HttpClient::NetworkError)
    end

    it 'wraps Errno::EHOSTUNREACH as NetworkError' do
      stub_request(:get, 'https://api.example.com/unreachable')
        .to_raise(Errno::EHOSTUNREACH)

      expect { client.get('/unreachable') }.to raise_error(Philiprehberger::HttpClient::NetworkError)
    end

    it 'wraps Errno::ENETUNREACH as NetworkError' do
      stub_request(:get, 'https://api.example.com/nonet')
        .to_raise(Errno::ENETUNREACH)

      expect { client.get('/nonet') }.to raise_error(Philiprehberger::HttpClient::NetworkError)
    end
  end

  describe 'fixed backoff delay' do
    it 'uses the same delay for each retry with fixed backoff' do
      client_fixed = described_class.new(
        base_url: base_url, retries: 3, retry_delay: 2, retry_backoff: :fixed
      )

      stub_request(:get, 'https://api.example.com/flaky')
        .to_raise(Errno::ECONNREFUSED)
        .then.to_raise(Errno::ECONNREFUSED)
        .then.to_raise(Errno::ECONNREFUSED)
        .then.to_return(status: 200, body: 'ok')

      allow(client_fixed).to receive(:sleep)

      response = client_fixed.get('/flaky')

      expect(response.status).to eq(200)
      expect(client_fixed).to have_received(:sleep).with(2).exactly(3).times
    end
  end

  describe 'request_count on errors' do
    it 'increments request_count even when request raises an error' do
      stub_request(:get, 'https://api.example.com/fail')
        .to_raise(SocketError)

      expect { client.get('/fail') }.to raise_error(Philiprehberger::HttpClient::NetworkError)
      expect(client.request_count).to eq(1)
    end
  end

  describe 'POST with empty JSON' do
    it 'sends an empty JSON object' do
      stub_request(:post, 'https://api.example.com/empty')
        .with(
          body: '{}',
          headers: { 'content-type' => 'application/json' }
        )
        .to_return(status: 200, body: '{}')

      response = client.post('/empty', json: {})

      expect(response.status).to eq(200)
      expect(response.json).to eq({})
    end

    it 'sends a JSON array body' do
      stub_request(:post, 'https://api.example.com/batch')
        .with(
          body: '[1,2,3]',
          headers: { 'content-type' => 'application/json' }
        )
        .to_return(status: 200, body: '{"count":3}')

      response = client.post('/batch', json: [1, 2, 3])

      expect(response.status).to eq(200)
    end
  end

  describe 'basic_auth with special characters' do
    it 'correctly encodes credentials containing colons' do
      client.basic_auth('user', 'p:a:ss')

      expected = Base64.strict_encode64('user:p:a:ss')

      stub_request(:get, 'https://api.example.com/secure')
        .with(headers: { 'authorization' => "Basic #{expected}" })
        .to_return(status: 200, body: 'ok')

      response = client.get('/secure')

      expect(response.status).to eq(200)
    end
  end

  describe 'bearer_token overrides basic_auth' do
    it 'replaces basic_auth header when bearer_token is set after' do
      client.basic_auth('user', 'pass')
      client.bearer_token('newtoken')

      stub_request(:get, 'https://api.example.com/auth')
        .with(headers: { 'authorization' => 'Bearer newtoken' })
        .to_return(status: 200, body: 'ok')

      response = client.get('/auth')

      expect(response.status).to eq(200)
    end
  end

  describe 'per-request headers' do
    it 'merges per-request headers with defaults' do
      client_with_defaults = described_class.new(
        base_url: base_url,
        headers: { 'x-api-key' => 'key123' }
      )

      stub_request(:get, 'https://api.example.com/data')
        .with(headers: { 'x-api-key' => 'key123', 'x-request-id' => 'req-1' })
        .to_return(status: 200, body: 'ok')

      response = client_with_defaults.get('/data', headers: { 'x-request-id' => 'req-1' })

      expect(response.status).to eq(200)
    end

    it 'per-request headers override default headers' do
      client_with_defaults = described_class.new(
        base_url: base_url,
        headers: { 'x-api-key' => 'default' }
      )

      stub_request(:get, 'https://api.example.com/data')
        .with(headers: { 'x-api-key' => 'override' })
        .to_return(status: 200, body: 'ok')

      response = client_with_defaults.get('/data', headers: { 'x-api-key' => 'override' })

      expect(response.status).to eq(200)
    end
  end

  describe 'Multipart boundary uniqueness' do
    it 'generates unique boundaries for each build call' do
      _, ct1 = Philiprehberger::HttpClient::Multipart.build({ a: '1' })
      _, ct2 = Philiprehberger::HttpClient::Multipart.build({ a: '1' })

      boundary1 = ct1.split('boundary=').last
      boundary2 = ct2.split('boundary=').last

      expect(boundary1).not_to eq(boundary2)
    end
  end

  # === Expanded coverage v0.4.6: edge cases and error paths ===

  describe 'HTTP vs HTTPS' do
    it 'disables SSL for http:// URLs' do
      http_client = described_class.new(base_url: 'http://api.example.com')

      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return('200')
      allow(raw_response).to receive(:body).and_return('ok')
      allow(raw_response).to receive(:each_header)
      allow(http_double).to receive(:request).and_return(raw_response)

      http_client.get('/test')

      expect(http_double).to have_received(:use_ssl=).with(false)
    end

    it 'enables SSL for https:// URLs' do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return('200')
      allow(raw_response).to receive(:body).and_return('ok')
      allow(raw_response).to receive(:each_header)
      allow(http_double).to receive(:request).and_return(raw_response)

      client.get('/test')

      expect(http_double).to have_received(:use_ssl=).with(true)
    end
  end

  describe 'GET with empty params' do
    it 'does not append query string when params hash is empty' do
      stub_request(:get, 'https://api.example.com/items')
        .to_return(status: 200, body: 'ok')

      response = client.get('/items', params: {})

      expect(response.status).to eq(200)
    end
  end

  describe 'Response#json with array body' do
    it 'parses a JSON array response' do
      stub_request(:get, 'https://api.example.com/list')
        .to_return(status: 200, body: '[1,2,3]')

      response = client.get('/list')

      expect(response.json).to eq([1, 2, 3])
    end
  end

  describe 'Response with nil body from server' do
    it 'returns empty string body when server sends nil body' do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return('204')
      allow(raw_response).to receive(:body).and_return(nil)
      allow(raw_response).to receive(:each_header)
      allow(http_double).to receive(:request).and_return(raw_response)

      response = client.get('/empty')

      expect(response.body).to eq('')
    end
  end

  describe 'multipart on PATCH' do
    it 'sends multipart body with PATCH request' do
      stub_request(:patch, 'https://api.example.com/resource/1')
        .with { |req| req.headers['Content-Type']&.include?('multipart/form-data') }
        .to_return(status: 200, body: 'ok')

      response = client.patch('/resource/1', multipart: { field: 'value' })

      expect(response.status).to eq(200)
    end
  end

  describe 'retry on status with non-retryable status' do
    it 'does not retry when status is not in retry_on_status list' do
      client_retry = described_class.new(
        base_url: base_url, retries: 2, retry_delay: 0, retry_on_status: [503]
      )

      stub_request(:get, 'https://api.example.com/not-found')
        .to_return(status: 404, body: 'not found')

      response = client_retry.get('/not-found')

      expect(response.status).to eq(404)
      expect(client_retry.request_count).to eq(1)
    end
  end

  describe 'retry with mixed network errors' do
    it 'retries across different network error types' do
      client_retry = described_class.new(base_url: base_url, retries: 3, retry_delay: 0)

      stub_request(:get, 'https://api.example.com/flaky')
        .to_raise(Errno::ECONNREFUSED)
        .then.to_raise(Errno::ECONNRESET)
        .then.to_raise(SocketError)
        .then.to_return(status: 200, body: 'ok')

      response = client_retry.get('/flaky')

      expect(response.status).to eq(200)
    end
  end

  describe 'request_count with retries' do
    it 'only increments request_count once per execute call, not per retry' do
      client_retry = described_class.new(base_url: base_url, retries: 2, retry_delay: 0)

      stub_request(:get, 'https://api.example.com/flaky')
        .to_raise(Errno::ECONNREFUSED)
        .then.to_return(status: 200, body: 'ok')

      client_retry.get('/flaky')

      expect(client_retry.request_count).to eq(1)
    end
  end

  describe 'DELETE with custom headers' do
    it 'sends per-request headers on DELETE' do
      stub_request(:delete, 'https://api.example.com/resource/1')
        .with(headers: { 'x-request-id' => 'del-123' })
        .to_return(status: 204, body: '')

      response = client.delete('/resource/1', headers: { 'x-request-id' => 'del-123' })

      expect(response.status).to eq(204)
    end
  end

  describe 'POST with form data containing special characters' do
    it 'correctly encodes special characters in form body' do
      stub_request(:post, 'https://api.example.com/search')
        .with(
          body: 'q=hello+world&tag=%26special%3D',
          headers: { 'content-type' => 'application/x-www-form-urlencoded' }
        )
        .to_return(status: 200, body: 'ok')

      response = client.post('/search', form: { q: 'hello world', tag: '&special=' })

      expect(response.status).to eq(200)
    end
  end

  describe 'interceptor context details' do
    it 'provides URI in request context' do
      captured_uri = nil

      client.use do |context|
        captured_uri = context[:request][:uri] unless context[:response]
      end

      stub_request(:get, 'https://api.example.com/info')
        .to_return(status: 200, body: 'ok')

      client.get('/info')

      expect(captured_uri.to_s).to include('api.example.com/info')
    end

    it 'provides method in request context for POST' do
      captured_method = nil

      client.use do |context|
        captured_method = context[:request][:method] unless context[:response]
      end

      stub_request(:post, 'https://api.example.com/data')
        .to_return(status: 201, body: 'ok')

      client.post('/data', json: { a: 1 })

      expect(captured_method).to eq('POST')
    end

    it 'provides headers in request context' do
      captured_headers = nil

      client.use do |context|
        captured_headers = context[:request][:headers] unless context[:response]
      end

      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 200, body: 'ok')

      client.get('/data', headers: { 'x-custom' => 'value' })

      expect(captured_headers).to be_a(Hash)
    end
  end

  describe 'exponential backoff delay calculation' do
    it 'calculates correct exponential delays for each attempt' do
      client_exp = described_class.new(
        base_url: base_url, retries: 2, retry_delay: 3, retry_backoff: :exponential
      )

      stub_request(:get, 'https://api.example.com/flaky')
        .to_raise(Errno::ECONNREFUSED)
        .then.to_raise(Errno::ECONNREFUSED)
        .then.to_return(status: 200, body: 'ok')

      allow(client_exp).to receive(:sleep)

      client_exp.get('/flaky')

      expect(client_exp).to have_received(:sleep).with(3).ordered
      expect(client_exp).to have_received(:sleep).with(6).ordered
    end
  end

  describe 'Response object construction' do
    it 'exposes all response headers' do
      stub_request(:get, 'https://api.example.com/headers')
        .to_return(
          status: 200,
          body: 'ok',
          headers: { 'x-ratelimit-remaining' => '99', 'x-request-id' => 'abc' }
        )

      response = client.get('/headers')

      expect(response.headers['x-ratelimit-remaining']).to eq('99')
      expect(response.headers['x-request-id']).to eq('abc')
    end

    it 'returns integer status codes' do
      stub_request(:get, 'https://api.example.com/test')
        .to_return(status: 201, body: 'created')

      response = client.get('/test')

      expect(response.status).to be_a(Integer)
    end
  end

  describe 'HttpError message format' do
    it 'includes status code and body excerpt in message' do
      response = Philiprehberger::HttpClient::Response.new(
        status: 502, body: 'Bad Gateway'
      )
      error = Philiprehberger::HttpClient::HttpError.new(response)

      expect(error.message).to eq('HTTP 502: Bad Gateway')
    end

    it 'handles nil body in error message' do
      response = Philiprehberger::HttpClient::Response.new(
        status: 504, body: nil
      )
      error = Philiprehberger::HttpClient::HttpError.new(response)

      expect(error.message).to include('HTTP 504')
    end
  end

  describe 'content-type not overridden when already set' do
    it 'preserves custom content-type for JSON body' do
      stub_request(:post, 'https://api.example.com/data')
        .with(
          body: '{"a":1}',
          headers: { 'content-type' => 'application/json; charset=utf-8' }
        )
        .to_return(status: 200, body: 'ok')

      response = client.post(
        '/data',
        json: { a: 1 },
        headers: { 'content-type' => 'application/json; charset=utf-8' }
      )

      expect(response.status).to eq(200)
    end

    it 'preserves custom content-type for form body' do
      stub_request(:post, 'https://api.example.com/data')
        .with(
          body: 'a=1',
          headers: { 'content-type' => 'application/x-www-form-urlencoded; charset=utf-8' }
        )
        .to_return(status: 200, body: 'ok')

      response = client.post(
        '/data',
        form: { a: '1' },
        headers: { 'content-type' => 'application/x-www-form-urlencoded; charset=utf-8' }
      )

      expect(response.status).to eq(200)
    end
  end

  describe 'CookieJar' do
    let(:jar) { Philiprehberger::HttpClient::CookieJar.new }

    it 'stores and retrieves cookies' do
      uri = URI.parse('https://example.com/path')
      jar.store('session=abc123; Path=/; HttpOnly', uri)

      expect(jar.cookie_header(uri)).to eq('session=abc123')
    end

    it 'returns nil when no cookies match' do
      uri = URI.parse('https://example.com/path')
      expect(jar.cookie_header(uri)).to be_nil
    end

    it 'respects domain matching' do
      uri = URI.parse('https://app.example.com/path')
      jar.store('token=xyz; Domain=example.com; Path=/', uri)

      expect(jar.cookie_header(URI.parse('https://app.example.com/'))).to eq('token=xyz')
      expect(jar.cookie_header(URI.parse('https://other.com/'))).to be_nil
    end

    it 'respects path matching' do
      uri = URI.parse('https://example.com/api/v1')
      jar.store('token=xyz; Path=/api', uri)

      expect(jar.cookie_header(URI.parse('https://example.com/api/v2'))).to eq('token=xyz')
      expect(jar.cookie_header(URI.parse('https://example.com/web'))).to be_nil
    end

    it 'replaces cookies with same name/domain/path' do
      uri = URI.parse('https://example.com/')
      jar.store('session=old; Path=/', uri)
      jar.store('session=new; Path=/', uri)

      expect(jar.size).to eq(1)
      expect(jar.cookie_header(uri)).to eq('session=new')
    end

    it 'clears all cookies' do
      uri = URI.parse('https://example.com/')
      jar.store('a=1; Path=/', uri)
      jar.store('b=2; Path=/', uri)
      jar.clear

      expect(jar.size).to eq(0)
    end

    it 'respects secure flag' do
      uri = URI.parse('https://example.com/')
      jar.store('token=abc; Secure; Path=/', uri)

      expect(jar.cookie_header(URI.parse('https://example.com/'))).to eq('token=abc')
      expect(jar.cookie_header(URI.parse('http://example.com/'))).to be_nil
    end
  end

  describe 'cookie jar integration' do
    let(:client) { described_class.new(base_url: base_url, cookies: true) }

    it 'exposes cookie_jar when cookies enabled' do
      expect(client.cookie_jar).to be_a(Philiprehberger::HttpClient::CookieJar)
    end

    it 'does not expose cookie_jar when cookies disabled' do
      no_cookie_client = described_class.new(base_url: base_url)
      expect(no_cookie_client.cookie_jar).to be_nil
    end

    it 'stores cookies from Set-Cookie response headers' do
      stub_request(:get, 'https://api.example.com/login')
        .to_return(status: 200, body: 'ok', headers: { 'set-cookie' => 'session=abc123; Path=/' })

      client.get('/login')
      expect(client.cookie_jar.size).to eq(1)
    end
  end

  describe 'Metrics' do
    it 'returns metrics on response' do
      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 200, body: 'hello')

      response = client.get('/data')
      expect(response.metrics).to be_a(Philiprehberger::HttpClient::Metrics)
      expect(response.metrics.total_time).to be >= 0
    end

    it 'provides timing as hash' do
      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 200, body: 'hello')

      response = client.get('/data')
      h = response.metrics.to_h
      expect(h).to include(:total_time, :first_byte_time, :dns_time, :connect_time, :tls_time)
    end
  end

  describe 'response decompression' do
    it 'decompresses gzip responses' do
      compressed = StringIO.new.tap do |io|
        gz = Zlib::GzipWriter.new(io)
        gz.write('hello world')
        gz.close
      end.string

      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 200, body: compressed, headers: { 'content-encoding' => 'gzip' })

      response = client.get('/data')
      expect(response.body).to eq('hello world')
    end

    it 'decompresses deflate responses' do
      compressed = Zlib::Deflate.deflate('hello deflate')

      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 200, body: compressed, headers: { 'content-encoding' => 'deflate' })

      response = client.get('/data')
      expect(response.body).to eq('hello deflate')
    end

    it 'passes through uncompressed responses' do
      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 200, body: 'plain text')

      response = client.get('/data')
      expect(response.body).to eq('plain text')
    end
  end

  describe 'redirect following' do
    it 'follows 302 redirects' do
      stub_request(:get, 'https://api.example.com/old')
        .to_return(status: 302, headers: { 'location' => 'https://api.example.com/new' })
      stub_request(:get, 'https://api.example.com/new')
        .to_return(status: 200, body: 'arrived')

      response = client.get('/old')
      expect(response.status).to eq(200)
      expect(response.body).to eq('arrived')
      expect(response.redirected?).to be true
      expect(response.redirects).to eq(['https://api.example.com/new'])
    end

    it 'follows 301 redirects' do
      stub_request(:get, 'https://api.example.com/moved')
        .to_return(status: 301, headers: { 'location' => 'https://api.example.com/final' })
      stub_request(:get, 'https://api.example.com/final')
        .to_return(status: 200, body: 'done')

      response = client.get('/moved')
      expect(response.status).to eq(200)
      expect(response.redirected?).to be true
    end

    it 'stops after max_redirects' do
      redirect_client = described_class.new(base_url: base_url, max_redirects: 2)

      stub_request(:get, 'https://api.example.com/a')
        .to_return(status: 302, headers: { 'location' => 'https://api.example.com/b' })
      stub_request(:get, 'https://api.example.com/b')
        .to_return(status: 302, headers: { 'location' => 'https://api.example.com/c' })
      stub_request(:get, 'https://api.example.com/c')
        .to_return(status: 302, headers: { 'location' => 'https://api.example.com/d' })

      response = redirect_client.get('/a')
      expect(response.status).to eq(302)
      expect(response.redirects.size).to eq(2)
    end

    it 'does not follow redirects when disabled' do
      no_redirect_client = described_class.new(base_url: base_url, follow_redirects: false)

      stub_request(:get, 'https://api.example.com/redir')
        .to_return(status: 302, headers: { 'location' => 'https://api.example.com/target' })

      response = no_redirect_client.get('/redir')
      expect(response.status).to eq(302)
      expect(response.redirected?).to be false
    end

    it 'reports no redirects for direct responses' do
      stub_request(:get, 'https://api.example.com/direct')
        .to_return(status: 200, body: 'ok')

      response = client.get('/direct')
      expect(response.redirected?).to be false
      expect(response.redirects).to eq([])
    end
  end

  describe 'on_request callback' do
    it 'calls the callback with method, uri, status, and duration after a request' do
      captured = nil
      callback_client = described_class.new(
        base_url: base_url,
        on_request: ->(method, uri, status, duration) { captured = { method: method, uri: uri, status: status, duration: duration } }
      )

      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 200, body: 'ok')

      callback_client.get('/data')

      expect(captured).not_to be_nil
      expect(captured[:method]).to eq('GET')
      expect(captured[:uri].to_s).to include('api.example.com/data')
      expect(captured[:status]).to eq(200)
      expect(captured[:duration]).to be_a(Float)
      expect(captured[:duration]).to be >= 0
    end

    it 'calls the callback for POST requests' do
      captured = nil
      callback_client = described_class.new(
        base_url: base_url,
        on_request: ->(method, _uri, status, _duration) { captured = { method: method, status: status } }
      )

      stub_request(:post, 'https://api.example.com/users')
        .to_return(status: 201, body: '{"id":1}')

      callback_client.post('/users', json: { name: 'Alice' })

      expect(captured[:method]).to eq('POST')
      expect(captured[:status]).to eq(201)
    end

    it 'does not raise when on_request is nil' do
      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 200, body: 'ok')

      expect { client.get('/data') }.not_to raise_error
    end

    it 'calls the callback for each request' do
      calls = []
      callback_client = described_class.new(
        base_url: base_url,
        on_request: ->(method, _uri, status, _duration) { calls << { method: method, status: status } }
      )

      stub_request(:get, 'https://api.example.com/a')
        .to_return(status: 200, body: 'ok')
      stub_request(:delete, 'https://api.example.com/b')
        .to_return(status: 204, body: '')

      callback_client.get('/a')
      callback_client.delete('/b')

      expect(calls.size).to eq(2)
      expect(calls[0]).to eq({ method: 'GET', status: 200 })
      expect(calls[1]).to eq({ method: 'DELETE', status: 204 })
    end

    it 'is called before response validation raises HttpError' do
      captured_status = nil
      callback_client = described_class.new(
        base_url: base_url,
        on_request: ->(_method, _uri, status, _duration) { captured_status = status }
      )

      stub_request(:get, 'https://api.example.com/fail')
        .to_return(status: 500, body: 'error')

      expect do
        callback_client.get('/fail', expect: [200])
      end.to raise_error(Philiprehberger::HttpClient::HttpError)

      expect(captured_status).to eq(500)
    end
  end

  describe 'proxy configuration' do
    it 'accepts proxy option' do
      proxy_client = described_class.new(base_url: base_url, proxy: 'http://proxy:8080')
      expect(proxy_client).to be_a(Philiprehberger::HttpClient::Client)
    end

    it 'works without proxy' do
      no_proxy_client = described_class.new(base_url: base_url)
      expect(no_proxy_client).to be_a(Philiprehberger::HttpClient::Client)
    end
  end

  describe 'Response initialization' do
    it 'initializes metrics as nil' do
      response = Philiprehberger::HttpClient::Response.new(status: 200, body: 'ok')
      expect(response.metrics).to be_nil
    end

    it 'initializes redirects as an empty array' do
      response = Philiprehberger::HttpClient::Response.new(status: 200, body: 'ok')
      expect(response.redirects).to eq([])
    end
  end

  describe '#close' do
    it 'can be called without error when pooling is disabled' do
      expect { client.close }.not_to raise_error
    end

    it 'can be called without error when pooling is enabled' do
      pooled_client = described_class.new(base_url: base_url, pool: true)
      expect { pooled_client.close }.not_to raise_error
    end
  end

  describe '.open' do
    it 'yields a client and returns the block value' do
      stub_request(:get, 'https://api.example.com/ping')
        .to_return(status: 200, body: 'pong')

      result = Philiprehberger::HttpClient.open(base_url: base_url) do |c|
        response = c.get('/ping')
        response.body
      end

      expect(result).to eq('pong')
    end

    it 'ensures close is called even if the block raises' do
      expect do
        Philiprehberger::HttpClient.open(base_url: base_url, pool: true) do |_c|
          raise 'boom'
        end
      end.to raise_error(RuntimeError, 'boom')
    end
  end
end
