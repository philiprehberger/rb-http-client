# frozen_string_literal: true

module Philiprehberger
  module HttpClient
    # Internal helpers for building URIs, HTTP connections, executing requests,
    # and constructing Response objects. Mixed into Client to keep it concise.
    module Connection
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

      def execute(uri, request, extra_headers, timeout: nil)
        apply_headers(request, extra_headers)
        @request_count += 1

        context = { request: { uri: uri, method: request.method, headers: request.to_hash } }
        run_interceptors(context)

        response = perform_with_retries(uri, request, timeout: timeout)
        context[:response] = response
        run_interceptors(context)

        response
      end

      def perform_with_retries(uri, request, timeout: nil)
        attempts = 0
        begin
          perform_request(uri, request, timeout: timeout)
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT,
               Net::OpenTimeout, Net::ReadTimeout, SocketError => e
          attempts += 1
          raise e unless attempts <= @retries

          delay = if @retry_backoff == :exponential
                    @retry_delay * (2**attempts)
                  else
                    @retry_delay
                  end
          sleep(delay)
          retry
        end
      end

      def perform_request(uri, request, timeout: nil)
        http = build_http(uri, timeout: timeout)
        raw = http.request(request)
        build_response(raw)
      end

      def build_http(uri, timeout: nil)
        effective_timeout = timeout || @timeout
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = effective_timeout
        http.read_timeout = effective_timeout
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
