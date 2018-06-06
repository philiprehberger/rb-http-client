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

      private

      def request_with_body(http_class, path, **opts, &block)
        headers = opts.fetch(:headers, {})
        uri = build_uri(path)
        request = http_class.new(uri)
        set_body(request, opts[:body], opts[:json], opts[:form], opts[:multipart], headers)
        execute(uri, request, headers, timeout: opts[:timeout], open_timeout: opts[:open_timeout],
                                       read_timeout: opts[:read_timeout], write_timeout: opts[:write_timeout],
                                       expect: opts[:expect], &block)
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

      def set_body(request, body, json_body, form_body, multipart_body, headers)
        if json_body
          request.body = JSON.generate(json_body)
          headers["content-type"] ||= "application/json"
        elsif form_body
          request.body = URI.encode_www_form(form_body)
          headers["content-type"] ||= "application/x-www-form-urlencoded"
        elsif multipart_body
          built_body, content_type = Multipart.build(multipart_body)
          request.body = built_body
          headers["content-type"] = content_type
        elsif body
          request.body = body
        end
      end

      def apply_headers(request, extra_headers)
        merged = @default_headers.merge(extra_headers)
        merged.each { |key, value| request[key] = value }
      end

      def execute(uri, request, extra_headers, timeout: nil, open_timeout: nil, read_timeout: nil,
                  write_timeout: nil, expect: nil, &block)
        apply_headers(request, extra_headers)
        @request_count += 1

        context = { request: { uri: uri, method: request.method, headers: request.to_hash } }
        run_interceptors(context)

        timeout_opts = { timeout: timeout, open_timeout: open_timeout,
                         read_timeout: read_timeout, write_timeout: write_timeout }

        response = perform_with_retries(uri, request, **timeout_opts, &block)
        context[:response] = response
        run_interceptors(context)

        validate_response!(response, expect) if expect

        response
      end

      def perform_with_retries(uri, request, **timeout_opts, &block)
        attempts = 0
        loop do
          response = perform_request(uri, request, **timeout_opts, &block)
          return response unless retry_on_status?(response.status, attempts)

          wait_and_retry(attempts += 1)
        rescue *TIMEOUT_ERRORS => e
          raise TimeoutError, e.message unless (attempts += 1) <= @retries

          sleep(retry_delay_for(attempts))
        rescue *NETWORK_ERRORS => e
          raise NetworkError, e.message unless (attempts += 1) <= @retries

          sleep(retry_delay_for(attempts))
        end
      end

      def retry_on_status?(status, attempts)
        @retry_on_status&.include?(status) && attempts < @retries
      end

      def wait_and_retry(attempt)
        sleep(retry_delay_for(attempt))
      end

      def retry_delay_for(attempt)
        @retry_backoff == :exponential ? @retry_delay * (2**(attempt - 1)) : @retry_delay
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

      def perform_streaming_request(http, request)
        response_headers = {}
        status = nil

        http.request(request) do |raw|
          status = raw.code.to_i
          raw.each_header { |k, v| response_headers[k] = v }
          raw.read_body do |chunk|
            yield chunk
          end
        end

        Response.new(status: status, body: nil, headers: response_headers, streaming: true)
      end

      def build_http(uri, timeout: nil, open_timeout: nil, read_timeout: nil, write_timeout: nil)
        effective_timeout = timeout || @timeout
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = open_timeout || @open_timeout || effective_timeout
        http.read_timeout = read_timeout || @read_timeout || effective_timeout
        http.write_timeout = write_timeout || @write_timeout || effective_timeout
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
