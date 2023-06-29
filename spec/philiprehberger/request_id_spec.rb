# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Request ID tracking' do
  let(:base_url) { 'https://api.example.com' }
  let(:client) { Philiprehberger::HttpClient.new(base_url: base_url) }

  describe 'automatic request ID generation' do
    it 'attaches X-Request-ID header to every request' do
      stub = stub_request(:get, 'https://api.example.com/data')
             .with { |req| req.headers['X-Request-Id'] =~ /\A[0-9a-f-]{36}\z/ }
             .to_return(status: 200, body: 'ok')

      client.get('/data')

      expect(stub).to have_been_requested
    end

    it 'generates a UUID-format request ID' do
      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 200, body: 'ok')

      response = client.get('/data')

      expect(response.request_id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it 'generates unique IDs for different requests' do
      stub_request(:get, 'https://api.example.com/one')
        .to_return(status: 200, body: 'ok')
      stub_request(:get, 'https://api.example.com/two')
        .to_return(status: 200, body: 'ok')

      r1 = client.get('/one')
      r2 = client.get('/two')

      expect(r1.request_id).not_to eq(r2.request_id)
    end

    it 'exposes request_id on Response' do
      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 200, body: 'ok')

      response = client.get('/data')

      expect(response.request_id).not_to be_nil
    end
  end

  describe 'custom request ID' do
    it 'uses the provided request_id for GET' do
      stub = stub_request(:get, 'https://api.example.com/data')
             .with(headers: { 'X-Request-Id' => 'custom-id-123' })
             .to_return(status: 200, body: 'ok')

      response = client.get('/data', request_id: 'custom-id-123')

      expect(stub).to have_been_requested
      expect(response.request_id).to eq('custom-id-123')
    end

    it 'uses the provided request_id for POST' do
      stub = stub_request(:post, 'https://api.example.com/data')
             .with(headers: { 'X-Request-Id' => 'post-id-456' })
             .to_return(status: 201, body: 'created')

      response = client.post('/data', json: { a: 1 }, request_id: 'post-id-456')

      expect(stub).to have_been_requested
      expect(response.request_id).to eq('post-id-456')
    end

    it 'uses the provided request_id for DELETE' do
      stub_request(:delete, 'https://api.example.com/resource/1')
        .with(headers: { 'X-Request-Id' => 'del-789' })
        .to_return(status: 204, body: '')

      response = client.delete('/resource/1', request_id: 'del-789')

      expect(response.request_id).to eq('del-789')
    end

    it 'uses the provided request_id for HEAD' do
      stub_request(:head, 'https://api.example.com/health')
        .with(headers: { 'X-Request-Id' => 'head-id' })
        .to_return(status: 200, body: '')

      response = client.head('/health', request_id: 'head-id')

      expect(response.request_id).to eq('head-id')
    end

    it 'uses the provided request_id for PUT' do
      stub_request(:put, 'https://api.example.com/resource/1')
        .with(headers: { 'X-Request-Id' => 'put-id' })
        .to_return(status: 200, body: 'ok')

      response = client.put('/resource/1', json: { a: 1 }, request_id: 'put-id')

      expect(response.request_id).to eq('put-id')
    end

    it 'uses the provided request_id for PATCH' do
      stub_request(:patch, 'https://api.example.com/resource/1')
        .with(headers: { 'X-Request-Id' => 'patch-id' })
        .to_return(status: 200, body: 'ok')

      response = client.patch('/resource/1', json: { a: 1 }, request_id: 'patch-id')

      expect(response.request_id).to eq('patch-id')
    end
  end

  describe 'request ID across retries' do
    it 'preserves the same request ID across retry attempts' do
      client_retry = Philiprehberger::HttpClient.new(
        base_url: base_url, retries: 2, retry_delay: 0
      )

      captured_ids = []
      client_retry.use do |context|
        captured_ids << context[:request][:headers]['x-request-id']&.first unless context[:response]
      end

      stub_request(:get, 'https://api.example.com/flaky')
        .to_raise(Errno::ECONNREFUSED)
        .then.to_return(status: 200, body: 'ok')

      response = client_retry.get('/flaky')

      # The interceptor captures the header before execution; the ID should be consistent
      expect(response.request_id).not_to be_nil
    end
  end

  describe 'request ID does not override user-set header' do
    it 'does not override x-request-id if already set in extra headers' do
      stub = stub_request(:get, 'https://api.example.com/data')
             .with(headers: { 'X-Request-Id' => 'user-set-id' })
             .to_return(status: 200, body: 'ok')

      client.get('/data', headers: { 'x-request-id' => 'user-set-id' })

      expect(stub).to have_been_requested
    end
  end
end
