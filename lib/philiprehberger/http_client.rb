# frozen_string_literal: true

require_relative 'http_client/version'
require_relative 'http_client/errors'
require_relative 'http_client/response'
require_relative 'http_client/multipart'
require_relative 'http_client/retries'
require_relative 'http_client/body_encoder'
require_relative 'http_client/connection'
require_relative 'http_client/client'

module Philiprehberger
  module HttpClient
    # Convenience constructor.
    #
    # @param options [Hash] Forwarded to {Client#initialize}
    # @return [Client]
    def self.new(**options)
      Client.new(**options)
    end
  end
end
