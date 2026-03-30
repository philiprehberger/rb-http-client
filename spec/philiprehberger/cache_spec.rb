# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Philiprehberger::HttpClient::Cache do
  let(:cache) { described_class.new }
  let(:uri) { URI.parse('https://api.example.com/data') }

  def make_response(status: 200, body: 'ok', headers: {})
    Philiprehberger::HttpClient::Response.new(status: status, body: body, headers: headers)
  end

  describe '#store and #lookup' do
    it 'stores and retrieves a response' do
      response = make_response
      cache.store(uri, response)

      expect(cache.lookup(uri)).to eq(response)
    end

    it 'returns nil for unknown URIs' do
      expect(cache.lookup(uri)).to be_nil
    end

    it 'does not cache responses with Cache-Control: no-store' do
      response = make_response(headers: { 'cache-control' => 'no-store' })
      cache.store(uri, response)

      expect(cache.lookup(uri)).to be_nil
    end

    it 'replaces existing entry for same URI' do
      response1 = make_response(body: 'first')
      response2 = make_response(body: 'second')
      cache.store(uri, response1)
      cache.store(uri, response2)

      expect(cache.lookup(uri).body).to eq('second')
    end

    it 'stores responses for different URIs independently' do
      uri2 = URI.parse('https://api.example.com/other')
      response1 = make_response(body: 'data1')
      response2 = make_response(body: 'data2')
      cache.store(uri, response1)
      cache.store(uri2, response2)

      expect(cache.lookup(uri).body).to eq('data1')
      expect(cache.lookup(uri2).body).to eq('data2')
    end
  end

  describe 'max-age expiration' do
    it 'returns nil for expired entries' do
      response = make_response(headers: { 'cache-control' => 'max-age=0' })
      cache.store(uri, response)

      # max-age=0 means immediately expired
      expect(cache.lookup(uri)).to be_nil
    end

    it 'returns cached response within max-age' do
      response = make_response(headers: { 'cache-control' => 'max-age=3600' })
      cache.store(uri, response)

      expect(cache.lookup(uri)).to eq(response)
    end

    it 'caches without max-age indefinitely' do
      response = make_response
      cache.store(uri, response)

      expect(cache.lookup(uri)).to eq(response)
    end
  end

  describe '#entry_for' do
    it 'returns the cache entry with etag' do
      response = make_response(headers: { 'etag' => '"abc123"' })
      cache.store(uri, response)

      entry = cache.entry_for(uri)

      expect(entry).not_to be_nil
      expect(entry.etag).to eq('"abc123"')
    end

    it 'returns the cache entry with last-modified' do
      response = make_response(headers: { 'last-modified' => 'Thu, 01 Jan 2026 00:00:00 GMT' })
      cache.store(uri, response)

      entry = cache.entry_for(uri)

      expect(entry).not_to be_nil
      expect(entry.last_modified).to eq('Thu, 01 Jan 2026 00:00:00 GMT')
    end

    it 'returns nil for unknown URIs' do
      expect(cache.entry_for(uri)).to be_nil
    end

    it 'returns entry even when expired (for conditional requests)' do
      response = make_response(headers: {
                                 'cache-control' => 'max-age=0',
                                 'etag' => '"expired-but-valid"'
                               })
      cache.store(uri, response)

      # lookup returns nil (expired)
      expect(cache.lookup(uri)).to be_nil
      # entry_for still returns the entry
      expect(cache.entry_for(uri)).not_to be_nil
      expect(cache.entry_for(uri).etag).to eq('"expired-but-valid"')
    end
  end

  describe '#clear!' do
    it 'removes all entries' do
      cache.store(uri, make_response)
      cache.store(URI.parse('https://other.com/'), make_response)
      cache.clear!

      expect(cache.size).to eq(0)
    end
  end

  describe '#size' do
    it 'returns the number of cached entries' do
      expect(cache.size).to eq(0)

      cache.store(uri, make_response)
      expect(cache.size).to eq(1)

      cache.store(URI.parse('https://other.com/'), make_response)
      expect(cache.size).to eq(2)
    end

    it 'does not count no-store responses' do
      cache.store(uri, make_response(headers: { 'cache-control' => 'no-store' }))
      expect(cache.size).to eq(0)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent store and lookup without errors' do
      threads = 10.times.map do |i|
        Thread.new do
          u = URI.parse("https://api.example.com/data/#{i}")
          cache.store(u, make_response(body: "body-#{i}"))
          cache.lookup(u)
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end
  end
end
