# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Philiprehberger
  module HttpClient
    class Client
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

      private

      def build_uri(path, params = {})
        url = "#{@base_url}/#{path.sub(%r{^/}, '')}"
        uri = URI.parse(url)
        unless params.empty?
          query = URI.encode_www_form(params)
          uri.query = uri.query ? "#{uri.query}&#{query}" : query
        end
        uri
      end

      def set_body(request, body, json_body, headers)
        if json_body
          request.body = JSON.generate(json_body)
          headers["content-type"] ||= "application/json"
        elsif body
          request.body = body
        end
      end

      def apply_headers(request, extra_headers)
        merged = @default_headers.merge(extra_headers)
        merged.each { |key, value| request[key] = value }
      end

      def execute(uri, request, extra_headers)
        apply_headers(request, extra_headers)

        context = { request: { uri: uri, method: request.method, headers: request.to_hash } }
        run_interceptors(context)

        response = perform_with_retries(uri, request)
        context[:response] = response
        run_interceptors(context)

        response
      end

      def perform_with_retries(uri, request)
        attempts = 0
        begin
          perform_request(uri, request)
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT,
               Net::OpenTimeout, Net::ReadTimeout, SocketError => e
          attempts += 1
          raise e unless attempts <= @retries

          sleep(@retry_delay)
          retry
        end
      end

      def perform_request(uri, request)
        http = build_http(uri)
        raw = http.request(request)
        build_response(raw)
      end

      def build_http(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @timeout
        http.read_timeout = @timeout
        http
      end

      def build_response(raw)
        response_headers = {}
        raw.each_header { |k, v| response_headers[k] = v }

        Response.new(
          status: raw.code.to_i,
          body: raw.body || "",
          headers: response_headers
        )
      end

      def run_interceptors(context)
        @interceptors.each { |interceptor| interceptor.call(context) }
      end
    end
  end
end
