# frozen_string_literal: true

require 'securerandom'

module Philiprehberger
  module HttpClient
    # Builds multipart/form-data request bodies from a hash of fields.
    # Supports both string values and File/IO objects.
    module Multipart
      CRLF = "\r\n"

      # Build a multipart/form-data body and content-type header.
      #
      # @param fields [Hash] field name => value pairs (String or File/IO)
      # @return [Array(String, String)] the body string and content-type header value
      def self.build(fields)
        boundary = generate_boundary
        body = build_body(fields, boundary)
        content_type = "multipart/form-data; boundary=#{boundary}"
        [body, content_type]
      end

      # @api private
      def self.generate_boundary
        "----RubyFormBoundary#{SecureRandom.hex(16)}"
      end

      # @api private
      def self.build_body(fields, boundary)
        parts = fields.map { |name, value| build_part(name, value, boundary) }
        parts.join + "--#{boundary}--#{CRLF}"
      end

      # @api private
      def self.build_part(name, value, boundary)
        if value.respond_to?(:read)
          build_file_part(name, value, boundary)
        else
          build_field_part(name, value, boundary)
        end
      end

      # @api private
      def self.build_file_part(name, file, boundary)
        filename = file.respond_to?(:path) ? File.basename(file.path) : 'upload'
        content = read_file_content(file)
        disposition = "Content-Disposition: form-data; name=\"#{name}\"; filename=\"#{filename}\"#{CRLF}"
        "--#{boundary}#{CRLF}#{disposition}Content-Type: application/octet-stream#{CRLF}#{CRLF}#{content}#{CRLF}"
      end

      def self.read_file_content(file)
        content = file.read
        file.rewind if file.respond_to?(:rewind)
        content
      end

      # @api private
      def self.build_field_part(name, value, boundary)
        ''.dup.tap do |part|
          part << "--#{boundary}#{CRLF}"
          part << "Content-Disposition: form-data; name=\"#{name}\"#{CRLF}"
          part << CRLF
          part << value.to_s
          part << CRLF
        end
      end
    end
  end
end
