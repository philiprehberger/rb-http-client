# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Philiprehberger
  module HttpClient
    class Client
      include Connection

      # @param base_url [String] Base URL for all requests
      # @param headers [Hash] Default headers applied to every request
      # @param timeout [Integer] Read/open timeout in seconds
      # @param retries [Integer] Number of retry attempts on network errors
      # @param retry_delay [Numeric] Seconds to wait between retries
      def initialize(base_url:, headers: {}, timeout: 30, retries: 0, retry_delay: 1)
        @base_url = base_url.chomp("/")
        @default_headers = headers
        @timeout = timeout
        @retries = retries
        @retry_delay = retry_delay
        @interceptors = []
      end

      # Register a request/response interceptor.
      #
      # The block receives a Hash with :request and, after the request completes, :response.
      # It is called twice: once before the request (with :request only) and once after
      # (with both :request and :response).
      #
      # @yield [Hash] context hash with :request and optionally :response
      # @return [self]
      def use(&block)
        @interceptors << block
        self
      end

      # Perform a GET request.
      #
      # @param path [String] Request path appended to the base URL
      # @param params [Hash] Query parameters
      # @param headers [Hash] Additional headers for this request
      # @return [Response]
      def get(path, params: {}, headers: {})
        uri = build_uri(path, params)
        request = Net::HTTP::Get.new(uri)
        execute(uri, request, headers)
      end

      # Perform a POST request.
      #
      # @param path [String] Request path
      # @param body [String, nil] Raw body string
      # @param json [Hash, Array, nil] JSON-serializable body (sets Content-Type automatically)
      # @param headers [Hash] Additional headers
      # @return [Response]
      def post(path, body: nil, json: nil, headers: {})
        uri = build_uri(path)
        request = Net::HTTP::Post.new(uri)
        set_body(request, body, json, headers)
        execute(uri, request, headers)
      end

      # Perform a PUT request.
      #
      # @param path [String] Request path
      # @param body [String, nil] Raw body string
      # @param json [Hash, Array, nil] JSON-serializable body
      # @param headers [Hash] Additional headers
      # @return [Response]
      def put(path, body: nil, json: nil, headers: {})
        uri = build_uri(path)
        request = Net::HTTP::Put.new(uri)
        set_body(request, body, json, headers)
        execute(uri, request, headers)
      end

      # Perform a PATCH request.
      #
      # @param path [String] Request path
      # @param body [String, nil] Raw body string
      # @param json [Hash, Array, nil] JSON-serializable body
      # @param headers [Hash] Additional headers
      # @return [Response]
      def patch(path, body: nil, json: nil, headers: {})
        uri = build_uri(path)
        request = Net::HTTP::Patch.new(uri)
        set_body(request, body, json, headers)
        execute(uri, request, headers)
      end

      # Perform a DELETE request.
      #
      # @param path [String] Request path
      # @param headers [Hash] Additional headers
      # @return [Response]
      def delete(path, headers: {})
        uri = build_uri(path)
        request = Net::HTTP::Delete.new(uri)
        execute(uri, request, headers)
      end
    end
  end
end
