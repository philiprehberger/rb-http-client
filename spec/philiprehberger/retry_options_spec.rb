# frozen_string_literal: true

require 'spec_helper'
require 'time'

RSpec.describe 'Retry options' do
  let(:base_url) { 'https://api.example.com' }

  describe 'Retry-After header' do
    it 'honors delta-seconds Retry-After as the retry delay' do
      client = Philiprehberger::HttpClient.new(
        base_url: base_url, retries: 2, retry_delay: 10, retry_on_status: [503]
      )

      stub_request(:get, 'https://api.example.com/slow')
        .to_return(status: 503, body: 'busy', headers: { 'retry-after' => '2' })
        .then.to_return(status: 200, body: 'ok')

      allow(client).to receive(:sleep)

      response = client.get('/slow')

      expect(response.status).to eq(200)
      expect(client).to have_received(:sleep).with(2)
    end

    it 'honors HTTP-date Retry-After as the retry delay' do
      client = Philiprehberger::HttpClient.new(
        base_url: base_url, retries: 1, retry_delay: 10, retry_on_status: [503]
      )

      future = (Time.now + 5).httpdate
      stub_request(:get, 'https://api.example.com/slow')
        .to_return(status: 503, body: 'busy', headers: { 'retry-after' => future })
        .then.to_return(status: 200, body: 'ok')

      allow(client).to receive(:sleep)

      client.get('/slow')

      expect(client).to have_received(:sleep).with(a_value_within(1.5).of(5))
    end

    it 'clamps an excessive Retry-After to the ceiling' do
      client = Philiprehberger::HttpClient.new(
        base_url: base_url, retries: 1, retry_delay: 1, retry_on_status: [503]
      )

      stub_request(:get, 'https://api.example.com/slow')
        .to_return(status: 503, body: 'busy', headers: { 'retry-after' => '100000' })
        .then.to_return(status: 200, body: 'ok')

      allow(client).to receive(:sleep)

      client.get('/slow')

      expect(client).to have_received(:sleep).with(
        Philiprehberger::HttpClient::Retries::RETRY_AFTER_CEILING
      )
    end

    it 'falls back to configured backoff when the header is absent' do
      client = Philiprehberger::HttpClient.new(
        base_url: base_url, retries: 1, retry_delay: 3, retry_on_status: [503]
      )

      stub_request(:get, 'https://api.example.com/slow')
        .to_return(status: 503, body: 'busy')
        .then.to_return(status: 200, body: 'ok')

      allow(client).to receive(:sleep)

      client.get('/slow')

      expect(client).to have_received(:sleep).with(3)
    end
  end

  describe 'backoff jitter and max delay cap' do
    it 'caps the exponential backoff at retry_max_delay' do
      client = Philiprehberger::HttpClient.new(
        base_url: base_url, retries: 4, retry_delay: 1,
        retry_backoff: :exponential, retry_max_delay: 5
      )

      stub_request(:get, 'https://api.example.com/flaky')
        .to_raise(Errno::ECONNREFUSED)
        .then.to_raise(Errno::ECONNREFUSED)
        .then.to_raise(Errno::ECONNREFUSED)
        .then.to_raise(Errno::ECONNREFUSED)
        .then.to_return(status: 200, body: 'ok')

      allow(client).to receive(:sleep)

      client.get('/flaky')

      # Uncapped sequence would be 1, 2, 4, 8 → capped at 5 → 1, 2, 4, 5
      expect(client).to have_received(:sleep).with(1).ordered
      expect(client).to have_received(:sleep).with(2).ordered
      expect(client).to have_received(:sleep).with(4).ordered
      expect(client).to have_received(:sleep).with(5).ordered
    end

    it 'applies full jitter to the (capped) delay when retry_jitter is true' do
      client = Philiprehberger::HttpClient.new(
        base_url: base_url, retries: 2, retry_delay: 4,
        retry_backoff: :exponential, retry_jitter: true
      )

      stub_request(:get, 'https://api.example.com/flaky')
        .to_raise(Errno::ECONNREFUSED)
        .then.to_raise(Errno::ECONNREFUSED)
        .then.to_return(status: 200, body: 'ok')

      allow(client).to receive(:jitter_rand).and_return(0.5)
      allow(client).to receive(:sleep)

      client.get('/flaky')

      # Backoff would be 4, then 8; full jitter with rand=0.5 → 2.0, 4.0
      expect(client).to have_received(:sleep).with(2.0).ordered
      expect(client).to have_received(:sleep).with(4.0).ordered
    end

    it 'does not apply jitter by default' do
      client = Philiprehberger::HttpClient.new(
        base_url: base_url, retries: 1, retry_delay: 2
      )

      stub_request(:get, 'https://api.example.com/flaky')
        .to_raise(Errno::ECONNREFUSED)
        .then.to_return(status: 200, body: 'ok')

      allow(client).to receive(:jitter_rand)
      allow(client).to receive(:sleep)

      client.get('/flaky')

      expect(client).not_to have_received(:jitter_rand)
      expect(client).to have_received(:sleep).with(2)
    end
  end

  describe 'option validation' do
    it 'rejects a non-boolean retry_jitter' do
      expect do
        Philiprehberger::HttpClient.new(base_url: base_url, retry_jitter: 'yes')
      end.to raise_error(Philiprehberger::HttpClient::ConfigurationError, /retry_jitter/)
    end

    it 'rejects a negative retry_max_delay' do
      expect do
        Philiprehberger::HttpClient.new(base_url: base_url, retry_max_delay: -1)
      end.to raise_error(Philiprehberger::HttpClient::ConfigurationError, /retry_max_delay/)
    end

    it 'rejects a non-numeric retry_max_delay' do
      expect do
        Philiprehberger::HttpClient.new(base_url: base_url, retry_max_delay: 'lots')
      end.to raise_error(Philiprehberger::HttpClient::ConfigurationError, /retry_max_delay/)
    end

    it 'rejects a non-positive cache_max_entries' do
      expect do
        Philiprehberger::HttpClient.new(base_url: base_url, cache: true, cache_max_entries: 0)
      end.to raise_error(Philiprehberger::HttpClient::ConfigurationError, /cache_max_entries/)
    end

    it 'wires cache_max_entries through to the cache' do
      client = Philiprehberger::HttpClient.new(base_url: base_url, cache: true, cache_max_entries: 42)
      expect(client.cache.max_entries).to eq(42)
    end
  end
end
