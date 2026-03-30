# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Response caching integration' do
  let(:base_url) { 'https://api.example.com' }

  describe 'cache: true option' do
    it 'creates a cache when cache: true' do
      client = Philiprehberger::HttpClient.new(base_url: base_url, cache: true)
      expect(client.cache).to be_a(Philiprehberger::HttpClient::Cache)
    end

    it 'does not create a cache by default' do
      client = Philiprehberger::HttpClient.new(base_url: base_url)
      expect(client.cache).to be_nil
    end
  end

  describe 'GET caching' do
    it 'caches GET responses' do
      client = Philiprehberger::HttpClient.new(base_url: base_url, cache: true)

      stub = stub_request(:get, 'https://api.example.com/data')
             .to_return(status: 200, body: '{"id":1}', headers: { 'cache-control' => 'max-age=3600' })

      # First request hits server
      r1 = client.get('/data')
      expect(r1.status).to eq(200)

      # Second request should return cached response
      r2 = client.get('/data')
      expect(r2.status).to eq(200)
      expect(r2.body).to eq('{"id":1}')

      # Server should only be called once
      expect(stub).to have_been_requested.once
    end

    it 'does not cache responses with Cache-Control: no-store' do
      client = Philiprehberger::HttpClient.new(base_url: base_url, cache: true)

      stub = stub_request(:get, 'https://api.example.com/private')
             .to_return(status: 200, body: 'secret', headers: { 'cache-control' => 'no-store' })

      client.get('/private')
      client.get('/private')

      expect(stub).to have_been_requested.twice
    end

    it 'does not cache non-GET requests' do
      client = Philiprehberger::HttpClient.new(base_url: base_url, cache: true)

      stub = stub_request(:post, 'https://api.example.com/data')
             .to_return(status: 201, body: 'created')

      client.post('/data', json: { a: 1 })
      client.post('/data', json: { a: 1 })

      expect(stub).to have_been_requested.twice
    end

    it 'does not cache streaming responses' do
      client = Philiprehberger::HttpClient.new(base_url: base_url, cache: true)

      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:write_timeout=)

      raw_response = Net::HTTPResponse.allocate
      allow(raw_response).to receive(:code).and_return('200')
      allow(raw_response).to receive(:each_header)
      allow(raw_response).to receive(:read_body).and_yield('chunk')
      allow(http_double).to receive(:request).and_yield(raw_response)

      client.get('/stream') { |_chunk| nil }

      expect(client.cache.size).to eq(0)
    end
  end

  describe '#clear_cache!' do
    it 'flushes the cache' do
      client = Philiprehberger::HttpClient.new(base_url: base_url, cache: true)

      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 200, body: 'ok', headers: { 'cache-control' => 'max-age=3600' })

      client.get('/data')
      expect(client.cache.size).to eq(1)

      client.clear_cache!
      expect(client.cache.size).to eq(0)
    end

    it 'is a no-op when caching is disabled' do
      client = Philiprehberger::HttpClient.new(base_url: base_url)
      expect { client.clear_cache! }.not_to raise_error
    end
  end

  describe 'conditional requests' do
    it 'sends If-None-Match for expired entries with ETag' do
      client = Philiprehberger::HttpClient.new(base_url: base_url, cache: true)

      # First request returns with ETag and short max-age
      stub_request(:get, 'https://api.example.com/data')
        .to_return(
          status: 200,
          body: 'original',
          headers: { 'cache-control' => 'max-age=0', 'etag' => '"abc123"' }
        ).then
        .to_return(status: 200, body: 'updated')

      client.get('/data')

      # Second request: cache expired, should send conditional header
      stub = stub_request(:get, 'https://api.example.com/data')
             .with(headers: { 'If-None-Match' => '"abc123"' })
             .to_return(status: 200, body: 'updated')

      client.get('/data')

      expect(stub).to have_been_requested
    end

    it 'sends If-Modified-Since for expired entries with Last-Modified' do
      client = Philiprehberger::HttpClient.new(base_url: base_url, cache: true)

      last_mod = 'Thu, 01 Jan 2026 00:00:00 GMT'

      stub_request(:get, 'https://api.example.com/data')
        .to_return(
          status: 200,
          body: 'original',
          headers: { 'cache-control' => 'max-age=0', 'last-modified' => last_mod }
        ).then
        .to_return(status: 200, body: 'updated')

      client.get('/data')

      stub = stub_request(:get, 'https://api.example.com/data')
             .with(headers: { 'If-Modified-Since' => last_mod })
             .to_return(status: 200, body: 'updated')

      client.get('/data')

      expect(stub).to have_been_requested
    end
  end

  describe 'does not cache error responses' do
    it 'does not cache 4xx responses' do
      client = Philiprehberger::HttpClient.new(base_url: base_url, cache: true)

      stub = stub_request(:get, 'https://api.example.com/missing')
             .to_return(status: 404, body: 'not found')

      client.get('/missing')
      client.get('/missing')

      expect(stub).to have_been_requested.twice
    end

    it 'does not cache 5xx responses' do
      client = Philiprehberger::HttpClient.new(base_url: base_url, cache: true)

      stub = stub_request(:get, 'https://api.example.com/error')
             .to_return(status: 500, body: 'server error')

      client.get('/error')
      client.get('/error')

      expect(stub).to have_been_requested.twice
    end
  end
end
