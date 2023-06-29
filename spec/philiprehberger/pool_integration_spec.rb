# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Connection pooling integration' do
  let(:base_url) { 'https://api.example.com' }

  describe 'pool: true option' do
    it 'creates a pool when pool: true' do
      client = Philiprehberger::HttpClient.new(base_url: base_url, pool: true)
      expect(client.pool).to be_a(Philiprehberger::HttpClient::Pool)
    end

    it 'creates a pool with default size' do
      client = Philiprehberger::HttpClient.new(base_url: base_url, pool: true)
      expect(client.pool.size).to eq(5)
    end

    it 'does not create a pool by default' do
      client = Philiprehberger::HttpClient.new(base_url: base_url)
      expect(client.pool).to be_nil
    end
  end

  describe 'pool_size option' do
    it 'creates a pool with custom size' do
      client = Philiprehberger::HttpClient.new(base_url: base_url, pool_size: 10)
      expect(client.pool).to be_a(Philiprehberger::HttpClient::Pool)
      expect(client.pool.size).to eq(10)
    end
  end

  describe 'pooled requests' do
    it 'makes requests successfully with pooling enabled' do
      client = Philiprehberger::HttpClient.new(base_url: base_url, pool: true)

      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 200, body: 'ok')

      response = client.get('/data')

      expect(response.status).to eq(200)
      expect(response.body).to eq('ok')
    end

    it 'makes multiple requests with pooling enabled' do
      client = Philiprehberger::HttpClient.new(base_url: base_url, pool: true)

      stub_request(:get, 'https://api.example.com/one')
        .to_return(status: 200, body: 'first')
      stub_request(:get, 'https://api.example.com/two')
        .to_return(status: 200, body: 'second')

      r1 = client.get('/one')
      r2 = client.get('/two')

      expect(r1.body).to eq('first')
      expect(r2.body).to eq('second')
    end
  end
end
