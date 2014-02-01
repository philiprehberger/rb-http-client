# frozen_string_literal: true

require_relative "http_client/version"
require_relative "http_client/response"
require_relative "http_client/client"

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
