# frozen_string_literal: true

require 'monitor'

module Philiprehberger
  module HttpClient
    # Simple in-memory cache for GET responses.
    # Respects Cache-Control headers (max-age, no-cache, no-store) and supports
    # conditional requests via ETag and Last-Modified headers.
    #
    # The store is bounded: once it holds +max_entries+ entries, the least
    # recently used entry is evicted on the next insert. Both {#lookup} hits
    # and {#refresh} mark an entry as recently used.
    #
    # @example
    #   cache = Cache.new(max_entries: 500)
    #   cache.store(uri, response)
    #   cached = cache.lookup(uri)
    class Cache
      # A cached entry with metadata for expiration and conditional requests.
      CacheEntry = Struct.new(:response, :stored_at, :max_age, :etag, :last_modified, keyword_init: true)

      # Default upper bound on the number of cached entries.
      DEFAULT_MAX_ENTRIES = 1000

      # @param max_entries [Integer] maximum number of entries retained before
      #   least-recently-used eviction kicks in (default: 1000)
      def initialize(max_entries: DEFAULT_MAX_ENTRIES)
        unless max_entries.is_a?(Integer) && max_entries.positive?
          raise ArgumentError, "max_entries must be a positive Integer, got #{max_entries.inspect}"
        end

        @monitor = Monitor.new
        @store = {}
        @max_entries = max_entries
      end

      # Maximum number of entries retained before LRU eviction.
      #
      # @return [Integer]
      attr_reader :max_entries

      # Look up a cached response for the given URI.
      # Returns nil if not cached or expired. A hit marks the entry as the most
      # recently used.
      #
      # @param uri [URI] the request URI
      # @return [Response, nil] the cached response or nil
      def lookup(uri)
        key = cache_key(uri)
        @monitor.synchronize do
          entry = @store[key]
          return nil unless entry

          if expired?(entry)
            # Keep entries with etag/last_modified for conditional requests
            @store.delete(key) unless entry.etag || entry.last_modified
            nil
          else
            touch(key, entry)
            entry.response
          end
        end
      end

      # Return the cache entry for conditional request headers.
      # Returns nil if no entry exists (even if expired).
      #
      # @param uri [URI] the request URI
      # @return [CacheEntry, nil]
      def entry_for(uri)
        key = cache_key(uri)
        @monitor.synchronize { @store[key] }
      end

      # Store a response in the cache.
      # Respects Cache-Control: no-store (does not cache). Evicts the least
      # recently used entry when the store exceeds +max_entries+.
      #
      # @param uri [URI] the request URI
      # @param response [Response] the response to cache
      # @return [void]
      def store(uri, response)
        return if no_store?(response)

        key = cache_key(uri)
        cc = parse_cache_control(response)

        entry = CacheEntry.new(
          response: response,
          stored_at: now,
          max_age: cc[:max_age],
          etag: response.headers['etag'],
          last_modified: response.headers['last-modified']
        )

        @monitor.synchronize do
          @store.delete(key)
          @store[key] = entry
          evict_lru
        end
      end

      # Refresh a stored entry after a 304 Not Modified revalidation.
      #
      # Resets +stored_at+ and applies any fresh +max-age+, +ETag+, or
      # +Last-Modified+ carried by the 304 response, then returns the stored
      # response (with its body) so the caller can serve cached content.
      # Marks the entry as most recently used. Returns nil when no entry exists
      # for the URI.
      #
      # @param uri [URI] the request URI
      # @param response [Response] the 304 Not Modified response
      # @return [Response, nil] the stored response, or nil if not cached
      def refresh(uri, response)
        key = cache_key(uri)
        cc = parse_cache_control(response)

        @monitor.synchronize do
          entry = @store[key]
          return nil unless entry

          entry.stored_at = now
          entry.max_age = cc[:max_age] if cc[:max_age]
          entry.etag = response.headers['etag'] if response.headers['etag']
          entry.last_modified = response.headers['last-modified'] if response.headers['last-modified']
          touch(key, entry)
          entry.response
        end
      end

      # Remove all entries from the cache.
      #
      # @return [void]
      def clear!
        @monitor.synchronize { @store.clear }
      end

      # Return the number of cached entries.
      #
      # @return [Integer]
      def size
        @monitor.synchronize { @store.size }
      end

      private

      def cache_key(uri)
        uri.to_s
      end

      # Move an existing key to the end of the insertion order, marking it as
      # the most recently used. Must be called while holding the monitor.
      def touch(key, entry)
        @store.delete(key)
        @store[key] = entry
      end

      # Evict least-recently-used entries (front of the insertion order) until
      # the store is within +max_entries+. Must be called while holding the monitor.
      def evict_lru
        @store.shift while @store.size > @max_entries
      end

      def expired?(entry)
        return false unless entry.max_age

        now - entry.stored_at > entry.max_age
      end

      def no_store?(response)
        cc = response.headers['cache-control']
        return false unless cc

        cc.include?('no-store')
      end

      def no_cache?(response)
        cc = response.headers['cache-control']
        return false unless cc

        cc.include?('no-cache')
      end

      def parse_cache_control(response)
        cc = response.headers['cache-control']
        result = { max_age: nil }
        return result unless cc

        if (match = cc.match(/max-age=(\d+)/))
          result[:max_age] = match[1].to_i
        end
        result
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
