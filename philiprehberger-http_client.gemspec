# frozen_string_literal: true

require_relative "lib/philiprehberger/http_client/version"

Gem::Specification.new do |spec|
  spec.name = "philiprehberger-http_client"
  spec.version = Philiprehberger::HttpClient::VERSION
  spec.authors = ["Philip Rehberger"]
  spec.email = ["me@philiprehberger.com"]

  spec.summary = "Lightweight HTTP client wrapper with retries and interceptors"
  spec.description = "A zero-dependency HTTP client built on Ruby's net/http with automatic retries, " \
    "request/response interceptors, and a clean API for JSON services."
  spec.homepage = "https://github.com/philiprehberger/rb-http-client"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    Dir["{lib}/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  end

  spec.require_paths = ["lib"]
end
