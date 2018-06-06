# frozen_string_literal: true

require "json"

module Philiprehberger
  module HttpClient
    class Response
      attr_reader :status, :body, :headers

      # @param status [Integer] HTTP status code
      # @param body [String, nil] Response body
      # @param headers [Hash] Response headers
      # @param streaming [Boolean] Whether the response was streamed
      def initialize(status:, body:, headers: {}, streaming: false)
        @status = status
        @body = body
        @headers = headers
        @streaming = streaming
      end

      # Returns true if the status code is in the 2xx range.
      #
      # @return [Boolean]
      def ok?
        status >= 200 && status < 300
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
    end
  end
end
