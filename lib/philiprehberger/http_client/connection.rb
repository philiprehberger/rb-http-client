# frozen_string_literal: true

require 'zlib'
require 'stringio'

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

      REDIRECT_CODES = [301, 302, 303, 307, 308].freeze

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
        request['accept-encoding'] ||= 'gzip, deflate'
        apply_cookie_header(request)
      end

      def apply_cookie_header(request)
        return unless @cookie_jar

        uri = URI.parse(request.uri.to_s) rescue return # rubocop:disable Style/RescueModifier
        cookie_value = @cookie_jar.cookie_header(uri)
        request['cookie'] = cookie_value if cookie_value
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
        response = follow_redirect_chain(response, request, **timeout_opts) if should_follow_redirect?(response)
        context[:response] = response
        run_interceptors(context)
        validate_response!(response, expect) if expect
        response
      end

      def perform_request(uri, request, **timeout_opts, &block)
        metrics = Metrics.new
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        http = build_http(uri, **timeout_opts)

        if block
          response = perform_streaming_request(http, request, &block)
        else
          raw = http.request(request)
          first_byte_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          metrics.record(:first_byte_time, first_byte_time - start_time)
          response = build_response(raw)
        end

        total_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        metrics.record(:total_time, total_time)
        store_cookies(response, uri)
        response.instance_variable_set(:@metrics, metrics)

        response
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
        http = if @proxy_uri
                 Net::HTTP.new(uri.host, uri.port, @proxy_uri.host, @proxy_uri.port,
                               proxy_user, proxy_password)
               else
                 Net::HTTP.new(uri.host, uri.port)
               end
        http.use_ssl = uri.scheme == 'https'
        apply_timeouts(http, timeout_opts)
        http
      end

      def proxy_user
        @proxy_uri&.user
      end

      def proxy_password
        @proxy_uri&.password
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
        body = decompress_body(raw.body || '', response_headers['content-encoding'])
        Response.new(status: raw.code.to_i, body: body, headers: response_headers)
      end

      def decompress_body(body, encoding)
        return body if body.empty?

        case encoding
        when 'gzip'
          Zlib::GzipReader.new(StringIO.new(body)).read
        when 'deflate'
          Zlib::Inflate.inflate(body)
        else
          body
        end
      rescue Zlib::Error
        body
      end

      def store_cookies(response, uri)
        return unless @cookie_jar

        Array(response.headers['set-cookie']).each do |cookie_header|
          @cookie_jar.store(cookie_header, uri)
        end
      end

      def should_follow_redirect?(response)
        @follow_redirects && REDIRECT_CODES.include?(response.status)
      end

      def follow_redirect_chain(response, original_request, **timeout_opts)
        redirect_count = 0
        redirects = []
        current_response = response

        while should_follow_redirect?(current_response) && redirect_count < @max_redirects
          location = current_response.headers['location']
          break unless location

          redirect_count += 1
          redirects << location
          redirect_uri = URI.parse(location)
          redirect_uri = URI.join("#{original_request.uri.scheme}://#{original_request.uri.host}", location) unless redirect_uri.host

          redirect_request = Net::HTTP::Get.new(redirect_uri)
          @default_headers.each { |key, value| redirect_request[key] = value }
          redirect_request['accept-encoding'] ||= 'gzip, deflate'
          apply_cookie_header(redirect_request)

          current_response = perform_request(redirect_uri, redirect_request, **timeout_opts)
        end

        current_response.instance_variable_set(:@redirects, redirects) unless redirects.empty?
        current_response
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
