# frozen_string_literal: true

module Philiprehberger
  module HttpClient
    # Base error class for all HTTP client errors.
    class Error < StandardError; end

    # Raised when client configuration is invalid (e.g. negative timeout).
    class ConfigurationError < Error; end

    # Raised when a connection or read timeout occurs.
    class TimeoutError < Error; end

    # Raised when a network-level error occurs (connection refused, reset, etc.).
    class NetworkError < Error; end

    # Raised when a response status does not match expected values.
    class HttpError < Error
      attr_reader :response

      # @param response [Response] the HTTP response that triggered the error
      def initialize(response)
        @response = response
        super("HTTP #{response.status}: #{response.body.to_s[0..200]}")
      end
    end
  end
end
