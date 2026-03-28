# frozen_string_literal: true

require 'time'

module Philiprehberger
  module HttpClient
    # Simple cookie jar that stores cookies across requests within a session.
    # Parses Set-Cookie headers and sends matching cookies back on subsequent requests.
    class CookieJar
      Cookie = Struct.new(:name, :value, :domain, :path, :expires, :secure, :http_only, keyword_init: true)

      def initialize
        @cookies = []
      end

      # Store cookies from a Set-Cookie response header.
      #
      # @param set_cookie_header [String] the Set-Cookie header value
      # @param request_uri [URI] the URI of the request that received the cookie
      def store(set_cookie_header, request_uri)
        return unless set_cookie_header

        cookie = parse_set_cookie(set_cookie_header, request_uri)
        return unless cookie

        @cookies.reject! { |c| c.name == cookie.name && c.domain == cookie.domain && c.path == cookie.path }
        @cookies << cookie
      end

      # Return the Cookie header value for a given URI.
      #
      # @param uri [URI] the request URI
      # @return [String, nil] cookie header value or nil if no cookies match
      def cookie_header(uri)
        purge_expired
        matching = @cookies.select { |c| matches?(c, uri) }
        return nil if matching.empty?

        matching.map { |c| "#{c.name}=#{c.value}" }.join('; ')
      end

      # Return all stored cookies.
      #
      # @return [Array<Cookie>]
      def to_a
        purge_expired
        @cookies.dup
      end

      # Remove all stored cookies.
      def clear
        @cookies.clear
      end

      # Return the number of stored cookies.
      #
      # @return [Integer]
      def size
        purge_expired
        @cookies.size
      end

      private

      def parse_set_cookie(header, request_uri)
        parts = header.split(';').map(&:strip)
        name_value = parts.shift
        return nil unless name_value&.include?('=')

        name, value = name_value.split('=', 2)
        attrs = parse_attributes(parts)

        Cookie.new(
          name: name.strip,
          value: value&.strip || '',
          domain: (attrs['domain'] || request_uri.host).downcase.sub(/^\./, ''),
          path: attrs['path'] || default_path(request_uri),
          expires: parse_expires(attrs),
          secure: attrs.key?('secure'),
          http_only: attrs.key?('httponly')
        )
      end

      def parse_attributes(parts)
        attrs = {}
        parts.each do |part|
          key, val = part.split('=', 2)
          attrs[key.strip.downcase] = val&.strip
        end
        attrs
      end

      def parse_expires(attrs)
        if attrs['max-age']
          Time.now + attrs['max-age'].to_i
        elsif attrs['expires']
          Time.parse(attrs['expires'])
        end
      rescue ArgumentError
        nil
      end

      def default_path(uri)
        path = uri.path
        return '/' if path.empty? || !path.start_with?('/')

        last_slash = path.rindex('/')
        last_slash&.positive? ? path[0...last_slash] : '/'
      end

      def matches?(cookie, uri)
        return false if cookie.secure && uri.scheme != 'https'
        return false unless domain_matches?(cookie.domain, uri.host)
        return false unless path_matches?(cookie.path, uri.path)

        true
      end

      def domain_matches?(cookie_domain, host)
        host = host.downcase
        cookie_domain = cookie_domain.downcase
        host == cookie_domain || host.end_with?(".#{cookie_domain}")
      end

      def path_matches?(cookie_path, request_path)
        request_path = '/' if request_path.empty?
        return true if cookie_path == '/'

        request_path == cookie_path || request_path.start_with?("#{cookie_path}/")
      end

      def purge_expired
        now = Time.now
        @cookies.reject! { |c| c.expires && c.expires < now }
      end
    end
  end
end
