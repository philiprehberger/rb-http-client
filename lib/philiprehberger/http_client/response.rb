# frozen_string_literal: true

require 'json'

module Philiprehberger
  module HttpClient
    class Response
      attr_reader :status, :body, :headers, :request_id

      # @param status [Integer] HTTP status code
      # @param body [String, nil] Response body
      # @param headers [Hash] Response headers
      # @param streaming [Boolean] Whether the response was streamed
      # @param request_id [String, nil] Request ID for tracking
      def initialize(status:, body:, headers: {}, streaming: false, request_id: nil)
        @status = status
        @body = body
        @headers = headers
        @streaming = streaming
        @request_id = request_id
        @metrics = nil
        @redirects = []
      end

      # Returns true if the status code is in the 2xx range.
      #
      # @return [Boolean]
      def ok?
        status >= 200 && status < 300
      end

      # Returns true if the status code is in the 4xx range.
      #
      # @return [Boolean]
      def client_error?
        status >= 400 && status < 500
      end

      # Returns true if the status code is in the 5xx range.
      #
      # @return [Boolean]
      def server_error?
        status >= 500 && status < 600
      end

      # Returns true if the response was streamed.
      #
      # @return [Boolean]
      def streaming?
        @streaming
      end

      # Parses the response body as JSON.
      #
      # @return [Hash, Array] Parsed JSON
      # @raise [JSON::ParserError] If the body is not valid JSON
      def json
        @json ||= JSON.parse(body)
      end

      # Returns the header value for `name`, matching case-insensitively.
      # Returns `nil` when the header is not present.
      #
      # @param name [String, Symbol] header name (case-insensitive)
      # @return [String, nil]
      def header(name)
        key = name.to_s.downcase
        headers.each { |k, v| return v if k.to_s.downcase == key }
        nil
      end

      # Returns true if the `Content-Type` response header advertises JSON.
      # Matches `application/json`, `application/problem+json`, and any
      # other `+json` structured-syntax suffix defined by RFC 6838.
      # Header lookup is case-insensitive.
      #
      # @return [Boolean]
      def json?
        value = header('content-type')
        return false unless value

        primary = value.to_s.downcase.split(';').first.to_s.strip
        primary == 'application/json' || primary.end_with?('+json')
      end

      # Returns request timing metrics (nil if not available).
      #
      # @return [Metrics, nil]
      attr_reader :metrics

      # Returns the redirect chain (empty if no redirects occurred).
      #
      # @return [Array<String>]
      attr_reader :redirects

      # Returns true if the response was redirected.
      #
      # @return [Boolean]
      def redirected?
        !redirects.empty?
      end
    end
  end
end
