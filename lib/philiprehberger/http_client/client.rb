# frozen_string_literal: true

require 'base64'
require 'net/http'
require 'securerandom'
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
      # @param cookies [Boolean] Enable cookie jar for automatic cookie handling
      # @param proxy [String, nil] Proxy URL (e.g., "http://proxy:8080"), also reads HTTP_PROXY/HTTPS_PROXY
      # @param follow_redirects [Boolean] Follow 3xx redirects (default: true)
      # @param max_redirects [Integer] Maximum number of redirects to follow (default: 5)
      # @param pool [Boolean, nil] Enable connection pooling (default: false)
      # @param pool_size [Integer, nil] Maximum connections per host:port (default: 5)
      # @param cache [Boolean, nil] Enable response caching for GET requests (default: false)
      # @param on_request [Proc, nil] Callback invoked after each request with (method, uri, status, duration)
      def initialize(base_url:, headers: {}, timeout: 30, **opts)
        @base_url = base_url.chomp('/')
        @default_headers = headers
        @timeout = timeout
        assign_timeout_opts(opts)
        assign_retry_opts(opts)
        assign_cookie_opts(opts)
        assign_proxy_opts(opts)
        assign_redirect_opts(opts)
        assign_pool_opts(opts)
        assign_cache_opts(opts)
        @on_request = opts[:on_request]
        @interceptors = []
        @request_count = 0
      end

      # Returns the total number of requests executed.
      #
      # @return [Integer]
      attr_reader :request_count

      # Returns the cookie jar (nil if cookies are disabled).
      #
      # @return [CookieJar, nil]
      attr_reader :cookie_jar

      # Returns the connection pool (nil if pooling is disabled).
      #
      # @return [Pool, nil]
      attr_reader :pool

      # Returns the response cache (nil if caching is disabled).
      #
      # @return [Cache, nil]
      attr_reader :cache

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
      # @param request_id [String, nil] Custom request ID (auto-generated if nil)
      # @yield [String] response body chunks when streaming
      # @return [Response]
      def get(path, params: {}, headers: {}, expect: nil, request_id: nil, **timeout_opts, &block)
        uri = build_uri(path, params)
        request = Net::HTTP::Get.new(uri)

        if @cache && !block
          cached = lookup_cache(uri, headers)
          return cached if cached
        end

        execute(uri, request, headers, expect: expect, request_id: request_id, **timeout_opts, &block)
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
      def head(path, params: {}, headers: {}, expect: nil, request_id: nil, **timeout_opts)
        uri = build_uri(path, params)
        request = Net::HTTP::Head.new(uri)
        execute(uri, request, headers, expect: expect, request_id: request_id, **timeout_opts)
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
      def delete(path, headers: {}, expect: nil, request_id: nil, **timeout_opts)
        uri = build_uri(path)
        request = Net::HTTP::Delete.new(uri)
        execute(uri, request, headers, expect: expect, request_id: request_id, **timeout_opts)
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

      # Flush the response cache. No-op if caching is disabled.
      #
      # @return [void]
      def clear_cache!
        @cache&.clear!
      end

      # Drain the connection pool. No-op if pooling is disabled.
      #
      # @return [void]
      def close
        @pool&.drain
      end

      # Create a client, yield it to the block, and ensure it is closed afterward.
      #
      # @param opts [Hash] Options forwarded to {#initialize}
      # @yield [Client] the client instance
      # @return [Object] the return value of the block
      def self.open(**opts)
        client = new(**opts)
        yield client
      ensure
        client&.close
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

      def assign_cookie_opts(opts)
        @cookie_jar = opts[:cookies] ? CookieJar.new : nil
      end

      def assign_proxy_opts(opts)
        @proxy_uri = resolve_proxy(opts[:proxy])
      end

      def assign_redirect_opts(opts)
        @follow_redirects = opts.fetch(:follow_redirects, true)
        @max_redirects = opts.fetch(:max_redirects, 5)
      end

      def assign_pool_opts(opts)
        pool_enabled = opts[:pool] || opts[:pool_size]
        pool_size = opts.fetch(:pool_size, 5)
        @pool = pool_enabled ? Pool.new(size: pool_size) : nil
      end

      def assign_cache_opts(opts)
        @cache = opts[:cache] ? Cache.new : nil
      end

      def lookup_cache(uri, extra_headers)
        cached = @cache.lookup(uri)
        return cached if cached

        entry = @cache.entry_for(uri)
        return nil unless entry

        apply_conditional_headers(extra_headers, entry)
        nil
      end

      def apply_conditional_headers(headers, entry)
        headers['if-none-match'] = entry.etag if entry.etag
        headers['if-modified-since'] = entry.last_modified if entry.last_modified
      end

      def resolve_proxy(proxy)
        return URI.parse(proxy) if proxy.is_a?(String)

        env_proxy = ENV['HTTPS_PROXY'] || ENV['HTTP_PROXY'] || ENV['https_proxy'] || ENV.fetch('http_proxy', nil)
        env_proxy ? URI.parse(env_proxy) : nil
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
