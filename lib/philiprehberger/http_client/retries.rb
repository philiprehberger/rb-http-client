# frozen_string_literal: true

module Philiprehberger
  module HttpClient
    # Retry logic extracted from Connection to keep module length manageable.
    module Retries
      private

      def perform_with_retries(uri, request, **timeout_opts, &block)
        attempts = 0
        loop do
          response = perform_request(uri, request, **timeout_opts, &block)
          return response unless retry_on_status?(response.status, attempts)

          wait_and_retry(attempts += 1)
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

      def wait_and_retry(attempt)
        sleep(retry_delay_for(attempt))
      end

      def retry_delay_for(attempt)
        @retry_backoff == :exponential ? @retry_delay * (2**(attempt - 1)) : @retry_delay
      end
    end
  end
end
