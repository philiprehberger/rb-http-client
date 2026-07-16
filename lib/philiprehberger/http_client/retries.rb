# frozen_string_literal: true

require 'time'

module Philiprehberger
  module HttpClient
    # Retry logic extracted from Connection to keep module length manageable.
    module Retries
      # Absolute ceiling (seconds) applied to a server-supplied Retry-After
      # value, guarding against pathological or hostile headers.
      RETRY_AFTER_CEILING = 300.0

      private

      def perform_with_retries(uri, request, **timeout_opts, &block)
        attempts = 0
        loop do
          response = perform_request(uri, request, **timeout_opts, &block)
          return response unless retry_on_status?(response.status, attempts)

          wait_and_retry(attempts += 1, response)
        rescue *Connection::TIMEOUT_ERRORS => e
          handle_retry_error(attempts += 1, TimeoutError, e.message)
        rescue *Connection::NETWORK_ERRORS => e
          handle_retry_error(attempts += 1, NetworkError, e.message)
        end
      end

      def handle_retry_error(attempts, error_class, message)
        raise error_class, message unless attempts <= @retries

        sleep(retry_delay_for(attempts))
      end

      def retry_on_status?(status, attempts)
        @retry_on_status&.include?(status) && attempts < @retries
      end

      def wait_and_retry(attempt, response = nil)
        sleep(retry_delay_for(attempt, response))
      end

      # Compute the delay before the next retry. A server-supplied Retry-After
      # header (delta-seconds or HTTP-date) takes precedence and is clamped to
      # {RETRY_AFTER_CEILING}; otherwise the configured backoff is used, capped
      # at +retry_max_delay+ and optionally randomized with full jitter.
      def retry_delay_for(attempt, response = nil)
        retry_after = response ? retry_after_delay(response) : nil
        return [retry_after, RETRY_AFTER_CEILING].min if retry_after

        apply_jitter(cap_delay(backoff_delay(attempt)))
      end

      def backoff_delay(attempt)
        @retry_backoff == :exponential ? @retry_delay * (2**(attempt - 1)) : @retry_delay
      end

      def cap_delay(delay)
        @retry_max_delay ? [delay, @retry_max_delay].min : delay
      end

      def apply_jitter(delay)
        return delay unless @retry_jitter

        jitter_rand * delay
      end

      # Random float in the half-open range [0.0, 1.0) used for full-jitter
      # backoff. Extracted so it can be stubbed in tests.
      #
      # @return [Float]
      def jitter_rand
        rand
      end

      # Parse a Retry-After response header into a delay in seconds.
      # Supports both delta-seconds (e.g. "120") and HTTP-date
      # (e.g. "Wed, 21 Oct 2026 07:28:00 GMT") forms. Returns nil when the
      # header is absent or unparseable.
      #
      # @param response [Response]
      # @return [Float, Integer, nil]
      def retry_after_delay(response)
        value = response.headers['retry-after']
        return nil unless value

        value = value.to_s.strip
        return value.to_i if value.match?(/\A\d+\z/)

        http_date_delay(value)
      end

      def http_date_delay(value)
        delay = Time.httpdate(value) - Time.now
        delay.negative? ? 0.0 : delay
      rescue ArgumentError
        nil
      end
    end
  end
end
