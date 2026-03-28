# frozen_string_literal: true

module Philiprehberger
  module HttpClient
    # Timing metrics for an HTTP request.
    # Captures DNS, connect, TLS, first byte, and total durations.
    class Metrics
      attr_reader :dns_time, :connect_time, :tls_time, :first_byte_time, :total_time

      def initialize
        @dns_time = 0.0
        @connect_time = 0.0
        @tls_time = 0.0
        @first_byte_time = 0.0
        @total_time = 0.0
      end

      # Record a timing measurement.
      #
      # @param field [Symbol] one of :dns_time, :connect_time, :tls_time, :first_byte_time, :total_time
      # @param value [Float] duration in seconds
      def record(field, value)
        instance_variable_set(:"@#{field}", value)
      end

      # Return all timings as a hash.
      #
      # @return [Hash{Symbol => Float}]
      def to_h
        {
          dns_time: @dns_time,
          connect_time: @connect_time,
          tls_time: @tls_time,
          first_byte_time: @first_byte_time,
          total_time: @total_time
        }
      end
    end
  end
end
