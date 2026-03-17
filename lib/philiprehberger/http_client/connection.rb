# frozen_string_literal: true

module Philiprehberger
  module HttpClient
    # Internal helpers for building URIs, HTTP connections, executing requests,
    # and constructing Response objects. Mixed into Client to keep it concise.
    module Connection
      TIMEOUT_ERRORS = [
        Net::OpenTimeout, Net::ReadTimeout
      ].freeze

      NETWORK_ERRORS = [
        Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT,
        Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError
      ].freeze

      RETRYABLE_ERRORS = (TIMEOUT_ERRORS + NETWORK_ERRORS).freeze

      include Retries
      include BodyEncoder

      private

      def request_with_body(http_class, path, **opts, &)
        headers = opts.fetch(:headers, {})
        uri = build_uri(path)
        request = http_class.new(uri)
        apply_body(request, opts, headers)
        execute(uri, request, headers, timeout: opts[:timeout], open_timeout: opts[:open_timeout],
                                       read_timeout: opts[:read_timeout], write_timeout: opts[:write_timeout],
                                       expect: opts[:expect], &)
      end

      def build_uri(path, params = {})
        url = "#{@base_url}/#{path.sub(%r{^/}, '')}"
        uri = URI.parse(url)
        unless params.empty?
          query = URI.encode_www_form(params)
          uri.query = uri.query ? "#{uri.query}&#{query}" : query
        end
        uri
      end

      def apply_headers(request, extra_headers)
        merged = @default_headers.merge(extra_headers)
        merged.each { |key, value| request[key] = value }
      end

      def execute(uri, request, extra_headers, expect: nil, **timeout_opts, &block)
        apply_headers(request, extra_headers)
        @request_count += 1
        run_execute_pipeline(uri, request, expect, **timeout_opts, &block)
      end

      def run_execute_pipeline(uri, request, expect, **timeout_opts, &)
        context = { request: { uri: uri, method: request.method, headers: request.to_hash } }
        run_interceptors(context)
        response = perform_with_retries(uri, request, **timeout_opts, &)
        context[:response] = response
        run_interceptors(context)
        validate_response!(response, expect) if expect
        response
      end

      def perform_request(uri, request, **timeout_opts, &block)
        http = build_http(uri, **timeout_opts)

        if block
          perform_streaming_request(http, request, &block)
        else
          raw = http.request(request)
          build_response(raw)
        end
      end

      def perform_streaming_request(http, request, &block)
        response_headers = {}
        status = nil

        http.request(request) do |raw|
          status = raw.code.to_i
          raw.each_header { |k, v| response_headers[k] = v }
          raw.read_body(&block)
        end

        Response.new(status: status, body: nil, headers: response_headers, streaming: true)
      end

      def build_http(uri, **timeout_opts)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        apply_timeouts(http, timeout_opts)
        http
      end

      def apply_timeouts(http, timeout_opts)
        effective = timeout_opts[:timeout] || @timeout
        http.open_timeout = resolve_timeout(:open_timeout, timeout_opts, effective)
        http.read_timeout = resolve_timeout(:read_timeout, timeout_opts, effective)
        http.write_timeout = resolve_timeout(:write_timeout, timeout_opts, effective)
      end

      def resolve_timeout(key, timeout_opts, fallback)
        timeout_opts[key] || instance_variable_get(:"@#{key}") || fallback
      end

      def build_response(raw)
        response_headers = {}
        raw.each_header { |k, v| response_headers[k] = v }
        Response.new(status: raw.code.to_i, body: raw.body || "", headers: response_headers)
      end

      def validate_response!(response, expected_statuses)
        return if expected_statuses.include?(response.status)

        raise HttpError, response
      end

      def run_interceptors(context)
        @interceptors.each { |interceptor| interceptor.call(context) }
      end
    end
  end
end
