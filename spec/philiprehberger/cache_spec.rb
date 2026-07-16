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

  describe '#refresh' do
    it 'returns the stored response (with body) for a cached URI' do
      stored = make_response(body: 'cached-body', headers: { 'etag' => '"v1"' })
      cache.store(uri, stored)

      not_modified = make_response(status: 304, body: nil)
      refreshed = cache.refresh(uri, not_modified)

      expect(refreshed).to eq(stored)
      expect(refreshed.body).to eq('cached-body')
    end

    it 'returns nil when no entry exists for the URI' do
      not_modified = make_response(status: 304, body: nil)
      expect(cache.refresh(uri, not_modified)).to be_nil
    end

    it 'resets freshness so an expired entry becomes servable again' do
      stored = make_response(body: 'cached-body', headers: { 'cache-control' => 'max-age=0', 'etag' => '"v1"' })
      cache.store(uri, stored)
      expect(cache.lookup(uri)).to be_nil # expired

      not_modified = make_response(status: 304, body: nil, headers: { 'cache-control' => 'max-age=3600' })
      cache.refresh(uri, not_modified)

      expect(cache.lookup(uri)).to eq(stored)
    end

    it 'adopts a new max-age from the 304 response' do
      stored = make_response(body: 'cached-body', headers: { 'cache-control' => 'max-age=0', 'etag' => '"v1"' })
      cache.store(uri, stored)

      cache.refresh(uri, make_response(status: 304, body: nil, headers: { 'cache-control' => 'max-age=600' }))

      entry = cache.entry_for(uri)
      expect(entry.max_age).to eq(600)
    end

    it 'adopts a new ETag from the 304 response' do
      stored = make_response(body: 'cached-body', headers: { 'etag' => '"v1"' })
      cache.store(uri, stored)

      cache.refresh(uri, make_response(status: 304, body: nil, headers: { 'etag' => '"v2"' }))

      expect(cache.entry_for(uri).etag).to eq('"v2"')
    end

    it 'keeps the previous ETag when the 304 omits one' do
      stored = make_response(body: 'cached-body', headers: { 'etag' => '"v1"' })
      cache.store(uri, stored)

      cache.refresh(uri, make_response(status: 304, body: nil))

      expect(cache.entry_for(uri).etag).to eq('"v1"')
    end
  end

  describe 'bounded LRU eviction' do
    it 'defaults max_entries to 1000' do
      expect(described_class.new.max_entries).to eq(1000)
    end

    it 'accepts a custom max_entries' do
      expect(described_class.new(max_entries: 5).max_entries).to eq(5)
    end

    it 'raises ArgumentError for a non-positive max_entries' do
      expect { described_class.new(max_entries: 0) }.to raise_error(ArgumentError)
      expect { described_class.new(max_entries: -1) }.to raise_error(ArgumentError)
      expect { described_class.new(max_entries: 'many') }.to raise_error(ArgumentError)
    end

    it 'never grows beyond max_entries' do
      bounded = described_class.new(max_entries: 3)
      5.times do |i|
        bounded.store(URI.parse("https://api.example.com/#{i}"), make_response(body: "b#{i}"))
      end

      expect(bounded.size).to eq(3)
    end

    it 'evicts the least recently used entry first' do
      bounded = described_class.new(max_entries: 2)
      a = URI.parse('https://api.example.com/a')
      b = URI.parse('https://api.example.com/b')
      c = URI.parse('https://api.example.com/c')

      bounded.store(a, make_response(body: 'a'))
      bounded.store(b, make_response(body: 'b'))
      # Touch 'a' so 'b' becomes the least recently used
      bounded.lookup(a)
      bounded.store(c, make_response(body: 'c'))

      expect(bounded.lookup(a)).not_to be_nil
      expect(bounded.lookup(b)).to be_nil # evicted
      expect(bounded.lookup(c)).not_to be_nil
    end

    it 'treats refresh as a use for LRU purposes' do
      bounded = described_class.new(max_entries: 2)
      a = URI.parse('https://api.example.com/a')
      b = URI.parse('https://api.example.com/b')
      c = URI.parse('https://api.example.com/c')

      bounded.store(a, make_response(body: 'a', headers: { 'etag' => '"a"' }))
      bounded.store(b, make_response(body: 'b'))
      bounded.refresh(a, make_response(status: 304, body: nil))
      bounded.store(c, make_response(body: 'c'))

      expect(bounded.lookup(a)).not_to be_nil
      expect(bounded.lookup(b)).to be_nil
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
