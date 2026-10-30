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

      # Returns the media type from the `Content-Type` header without any
      # parameters (e.g. `"application/json"` for
      # `"application/json; charset=utf-8"`). The value is downcased.
      #
      # @return [String, nil] the media type, or `nil` if the header is absent or blank
      def content_type
        value = header('content-type')
        return nil if value.nil?

        media_type = value.to_s.split(';').first.to_s.strip.downcase
        media_type.empty? ? nil : media_type
      end

      # Returns the `Content-Length` header as an Integer.
      #
      # @return [Integer, nil] the declared body length, or `nil` if the header
      #   is absent or not a valid non-negative integer
      def content_length
        value = header('content-length')
        return nil if value.nil?

        length = Integer(value.to_s.strip, 10, exception: false)
        length&.negative? ? nil : length
      end

      # Raises {HttpError} if the response has a 4xx or 5xx status code.
      # Returns `self` otherwise so the call can be chained.
      #
      # @example
      #   data = client.get('/users').raise_for_status!.json
      #
      # @return [self]
      # @raise [HttpError] if the status code is 400 or greater
      def raise_for_status!
        raise HttpError, self if status >= 400

        self
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
