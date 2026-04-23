# frozen_string_literal: true

require_relative 'http_client/version'
require_relative 'http_client/errors'
require_relative 'http_client/response'
require_relative 'http_client/multipart'
require_relative 'http_client/retries'
require_relative 'http_client/body_encoder'
require_relative 'http_client/cookie_jar'
require_relative 'http_client/metrics'
require_relative 'http_client/pool'
require_relative 'http_client/cache'
require_relative 'http_client/connection'
require_relative 'http_client/client'

module Philiprehberger
  module HttpClient
    # Convenience constructor that instantiates a new {Client}.
    #
    # This is a thin wrapper around {Client.new} so callers can write
    # `Philiprehberger::HttpClient.new(base_url: '...')` without reaching
    # into the nested {Client} constant.
    #
    # @param options [Hash] Keyword options forwarded to {Client#initialize}
    #   (e.g. `base_url:`, `headers:`, `timeout:`, `retries:`, `pool:`, `cache:`)
    # @return [Client] a new configured client instance
    def self.new(**options)
      Client.new(**options)
    end

    # Block form constructor — creates a {Client}, yields it, and guarantees
    # cleanup by calling `#close` in an `ensure` block when the block exits.
    #
    # Equivalent to {Client.open}; prefer this form when you want automatic
    # connection pool draining without manually calling `#close`.
    #
    # @param options [Hash] Keyword options forwarded to {Client#initialize}
    # @yield [client] yields the client instance to the block
    # @yieldparam client [Client] the newly created client
    # @return [Object] the return value of the block
    def self.open(...)
      Client.open(...)
    end
  end
end
