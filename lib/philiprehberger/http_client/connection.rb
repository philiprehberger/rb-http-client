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
