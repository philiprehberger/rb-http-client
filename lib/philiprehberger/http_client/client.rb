# frozen_string_literal: true

require 'base64'
require 'net/http'
require 'uri'
require 'json'

module Philiprehberger
  module HttpClient
    class Client
      include Connection

      # @param base_url [String] Base URL for all requests
      # @param headers [Hash] Default headers applied to every request
      # @param timeout [Integer] General read/open timeout in seconds
      # @param open_timeout [Integer, nil] TCP connection timeout (overrides timeout)
      # @param read_timeout [Integer, nil] Response read timeout (overrides timeout)
      # @param write_timeout [Integer, nil] Request write timeout (overrides timeout)
      # @param retries [Integer] Number of retry attempts on network errors
      # @param retry_delay [Numeric] Seconds to wait between retries
      # @param retry_backoff [Symbol] Backoff strategy (:fixed or :exponential)
      def initialize(base_url:, headers: {}, timeout: 30, **opts)
        @base_url = base_url.chomp('/')
        @default_headers = headers
        @timeout = timeout
        assign_timeout_opts(opts)
        assign_retry_opts(opts)
        @interceptors = []
        @request_count = 0
      end

      # Returns the total number of requests executed.
      #
      # @return [Integer]
      attr_reader :request_count

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
      # @param timeout [Integer, nil] Optional per-request timeout override
      # @param open_timeout [Integer, nil] Optional per-request open timeout
      # @param read_timeout [Integer, nil] Optional per-request read timeout
      # @param write_timeout [Integer, nil] Optional per-request write timeout
      # @param expect [Array<Integer>, nil] Expected status codes (raises HttpError otherwise)
      # @yield [String] response body chunks when streaming
      # @return [Response]
      def get(path, params: {}, headers: {}, expect: nil, **timeout_opts, &block)
        uri = build_uri(path, params)
        request = Net::HTTP::Get.new(uri)
        execute(uri, request, headers, expect: expect, **timeout_opts, &block)
      end

      # Perform a HEAD request.
      #
      # @param path [String] Request path appended to the base URL
      # @param params [Hash] Query parameters
      # @param headers [Hash] Additional headers for this request
      # @param timeout [Integer, nil] Optional per-request timeout override
      # @param open_timeout [Integer, nil] Optional per-request open timeout
      # @param read_timeout [Integer, nil] Optional per-request read timeout
      # @param write_timeout [Integer, nil] Optional per-request write timeout
      # @param expect [Array<Integer>, nil] Expected status codes
      # @return [Response]
      def head(path, params: {}, headers: {}, expect: nil, **timeout_opts)
        uri = build_uri(path, params)
        request = Net::HTTP::Head.new(uri)
        execute(uri, request, headers, expect: expect, **timeout_opts)
      end

      # Perform a POST request.
      #
      # @param path [String] Request path
      # @param body [String, nil] Raw body string
      # @param json [Hash, Array, nil] JSON-serializable body (sets Content-Type automatically)
      # @param form [Hash, nil] Form-urlencoded body (sets Content-Type automatically)
      # @param multipart [Hash, nil] Multipart form data (sets Content-Type automatically)
      # @param headers [Hash] Additional headers
      # @param expect [Array<Integer>, nil] Expected status codes
      # @return [Response]
      def post(path, ...)
        request_with_body(Net::HTTP::Post, path, ...)
      end

      # Perform a PUT request.
      #
      # @param path [String] Request path
      # @param body [String, nil] Raw body string
      # @param json [Hash, Array, nil] JSON-serializable body
      # @param form [Hash, nil] Form-urlencoded body
      # @param multipart [Hash, nil] Multipart form data
      # @param headers [Hash] Additional headers
      # @param expect [Array<Integer>, nil] Expected status codes
      # @return [Response]
      def put(path, ...)
        request_with_body(Net::HTTP::Put, path, ...)
      end

      # Perform a PATCH request.
      #
      # @param path [String] Request path
      # @param body [String, nil] Raw body string
      # @param json [Hash, Array, nil] JSON-serializable body
      # @param form [Hash, nil] Form-urlencoded body
      # @param multipart [Hash, nil] Multipart form data
      # @param headers [Hash] Additional headers
      # @param expect [Array<Integer>, nil] Expected status codes
      # @return [Response]
      def patch(path, ...)
        request_with_body(Net::HTTP::Patch, path, ...)
      end

      # Perform a DELETE request.
      #
      # @param path [String] Request path
      # @param headers [Hash] Additional headers
      # @param timeout [Integer, nil] Optional per-request timeout override
      # @param open_timeout [Integer, nil] Optional per-request open timeout
      # @param read_timeout [Integer, nil] Optional per-request read timeout
      # @param write_timeout [Integer, nil] Optional per-request write timeout
      # @param expect [Array<Integer>, nil] Expected status codes
      # @return [Response]
      def delete(path, headers: {}, expect: nil, **timeout_opts)
        uri = build_uri(path)
        request = Net::HTTP::Delete.new(uri)
        execute(uri, request, headers, expect: expect, **timeout_opts)
      end

      # Set a Bearer token for all subsequent requests.
      #
      # @param token [String] the bearer token
      # @return [self]
      def bearer_token(token)
        @default_headers['authorization'] = "Bearer #{token}"
        self
      end

      # Set Basic auth credentials for all subsequent requests.
      #
      # @param username [String]
      # @param password [String]
      # @return [self]
      def basic_auth(username, password)
        encoded = Base64.strict_encode64("#{username}:#{password}")
        @default_headers['authorization'] = "Basic #{encoded}"
        self
      end

      private

      def assign_timeout_opts(opts)
        @open_timeout = opts[:open_timeout]
        @read_timeout = opts[:read_timeout]
        @write_timeout = opts[:write_timeout]
      end

      def assign_retry_opts(opts)
        @retries = opts.fetch(:retries, 0)
        @retry_delay = opts.fetch(:retry_delay, 1)
        @retry_backoff = opts.fetch(:retry_backoff, :fixed)
        @retry_on_status = opts[:retry_on_status]
      end
    end
  end
end
