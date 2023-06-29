# frozen_string_literal: true

require 'monitor'

module Philiprehberger
  module HttpClient
    # Thread-safe connection pool that reuses Net::HTTP connections to the same host:port.
    # Idle connections are automatically expired after the configured timeout.
    #
    # @example
    #   pool = Pool.new(size: 5, idle_timeout: 60)
    #   conn = pool.checkout(uri)
    #   # ... use conn ...
    #   pool.checkin(uri, conn)
    class Pool
      # @param size [Integer] maximum number of connections per host:port
      # @param idle_timeout [Integer] seconds before an idle connection is expired
      def initialize(size: 5, idle_timeout: 60)
        @size = size
        @idle_timeout = idle_timeout
        @monitor = Monitor.new
        @pools = {}
      end

      # Returns the maximum pool size.
      #
      # @return [Integer]
      attr_reader :size

      # Returns the idle timeout in seconds.
      #
      # @return [Integer]
      attr_reader :idle_timeout

      # Check out a connection for the given URI's host:port.
      # Returns an existing idle connection if available, or nil if none are available.
      #
      # @param uri [URI] the request URI
      # @return [Net::HTTP, nil] a reusable connection or nil
      def checkout(uri)
        key = pool_key(uri)
        @monitor.synchronize do
          entries = @pools[key] || []
          purge_expired(entries)
          @pools[key] = entries

          entry = entries.shift
          entry&.fetch(:connection)
        end
      end

      # Return a connection to the pool for reuse.
      #
      # @param uri [URI] the request URI
      # @param connection [Net::HTTP] the connection to return
      # @return [void]
      def checkin(uri, connection)
        key = pool_key(uri)
        @monitor.synchronize do
          entries = @pools[key] ||= []
          purge_expired(entries)

          if entries.size < @size
            entries.push({ connection: connection, checked_in_at: now })
          else
            safe_finish(connection)
          end
        end
      end

      # Close all pooled connections and clear the pool.
      #
      # @return [void]
      def drain
        @monitor.synchronize do
          @pools.each_value do |entries|
            entries.each { |entry| safe_finish(entry[:connection]) }
          end
          @pools.clear
        end
      end

      # Return the number of idle connections across all hosts.
      #
      # @return [Integer]
      def idle_count
        @monitor.synchronize do
          @pools.values.sum(&:size)
        end
      end

      private

      def pool_key(uri)
        "#{uri.host}:#{uri.port}"
      end

      def purge_expired(entries)
        cutoff = now - @idle_timeout
        entries.reject! do |entry|
          if entry[:checked_in_at] < cutoff
            safe_finish(entry[:connection])
            true
          else
            false
          end
        end
      end

      def safe_finish(connection)
        connection.finish if connection.started?
      rescue IOError
        # Connection already closed
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
