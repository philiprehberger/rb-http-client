# frozen_string_literal: true

require 'monitor'

module Philiprehberger
  module HttpClient
    # Simple in-memory cache for GET responses.
    # Respects Cache-Control headers (max-age, no-cache, no-store) and supports
    # conditional requests via ETag and Last-Modified headers.
    #
    # @example
    #   cache = Cache.new
    #   cache.store(uri, response)
    #   cached = cache.lookup(uri)
    class Cache
      # A cached entry with metadata for expiration and conditional requests.
      CacheEntry = Struct.new(:response, :stored_at, :max_age, :etag, :last_modified, keyword_init: true)

      def initialize
        @monitor = Monitor.new
        @store = {}
      end

      # Look up a cached response for the given URI.
      # Returns nil if not cached or expired.
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
      # Respects Cache-Control: no-store (does not cache).
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

        @monitor.synchronize { @store[key] = entry }
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
