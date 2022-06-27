# frozen_string_literal: true

module Philiprehberger
  module HttpClient
    # Handles encoding request bodies (JSON, form, multipart, raw).
    module BodyEncoder
      private

      def apply_body(request, opts, headers)
        set_json_body(request, opts[:json], headers) ||
          set_form_body(request, opts[:form], headers) ||
          set_multipart_body(request, opts[:multipart], headers) ||
          set_raw_body(request, opts[:body])
      end

      def set_json_body(request, json_body, headers)
        return unless json_body

        request.body = JSON.generate(json_body)
        headers['content-type'] ||= 'application/json'
      end

      def set_form_body(request, form_body, headers)
        return unless form_body

        request.body = URI.encode_www_form(form_body)
        headers['content-type'] ||= 'application/x-www-form-urlencoded'
      end

      def set_multipart_body(request, multipart_body, headers)
        return unless multipart_body

        built_body, content_type = Multipart.build(multipart_body)
        request.body = built_body
        headers['content-type'] = content_type
      end

      def set_raw_body(request, body)
        request.body = body if body
      end
    end
  end
end
