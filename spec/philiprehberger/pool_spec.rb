# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Philiprehberger::HttpClient::Pool do
  let(:pool) { described_class.new(size: 3, idle_timeout: 60) }
  let(:uri) { URI.parse('https://api.example.com/path') }

  describe '#initialize' do
    it 'creates a pool with given size' do
      expect(pool.size).to eq(3)
    end

    it 'creates a pool with given idle_timeout' do
      expect(pool.idle_timeout).to eq(60)
    end

    it 'defaults to size 5 and idle_timeout 60' do
      default_pool = described_class.new
      expect(default_pool.size).to eq(5)
      expect(default_pool.idle_timeout).to eq(60)
    end

    it 'starts with zero idle connections' do
      expect(pool.idle_count).to eq(0)
    end
  end

  describe '#checkout' do
    it 'returns nil when no connections are available' do
      expect(pool.checkout(uri)).to be_nil
    end

    it 'returns a previously checked-in connection' do
      conn = instance_double(Net::HTTP)
      allow(conn).to receive(:started?).and_return(false)
      pool.checkin(uri, conn)

      expect(pool.checkout(uri)).to eq(conn)
    end

    it 'returns nil after all connections are checked out' do
      conn = instance_double(Net::HTTP)
      allow(conn).to receive(:started?).and_return(false)
      pool.checkin(uri, conn)
      pool.checkout(uri)

      expect(pool.checkout(uri)).to be_nil
    end

    it 'does not return connections for different hosts' do
      conn = instance_double(Net::HTTP)
      allow(conn).to receive(:started?).and_return(false)
      pool.checkin(uri, conn)

      other_uri = URI.parse('https://other.example.com/path')
      expect(pool.checkout(other_uri)).to be_nil
    end
  end

  describe '#checkin' do
    it 'stores a connection for later reuse' do
      conn = instance_double(Net::HTTP)
      allow(conn).to receive(:started?).and_return(false)
      pool.checkin(uri, conn)

      expect(pool.idle_count).to eq(1)
    end

    it 'respects pool size limit' do
      conns = 4.times.map do
        conn = instance_double(Net::HTTP)
        allow(conn).to receive(:started?).and_return(false)
        allow(conn).to receive(:finish)
        conn
      end

      conns.each { |c| pool.checkin(uri, c) }

      # Pool size is 3, so fourth connection should be finished
      expect(pool.idle_count).to eq(3)
      expect(conns[3]).to have_received(:started?)
    end

    it 'finishes excess connections when pool is full' do
      conn_excess = instance_double(Net::HTTP)
      allow(conn_excess).to receive(:started?).and_return(true)
      allow(conn_excess).to receive(:finish)

      3.times do
        c = instance_double(Net::HTTP)
        allow(c).to receive(:started?).and_return(false)
        pool.checkin(uri, c)
      end

      pool.checkin(uri, conn_excess)

      expect(conn_excess).to have_received(:finish)
    end
  end

  describe '#drain' do
    it 'closes all pooled connections' do
      conn1 = instance_double(Net::HTTP)
      allow(conn1).to receive(:started?).and_return(true)
      allow(conn1).to receive(:finish)

      conn2 = instance_double(Net::HTTP)
      allow(conn2).to receive(:started?).and_return(false)

      pool.checkin(uri, conn1)
      pool.checkin(uri, conn2)
      pool.drain

      expect(pool.idle_count).to eq(0)
      expect(conn1).to have_received(:finish)
    end
  end

  describe '#idle_count' do
    it 'counts connections across multiple hosts' do
      conn1 = instance_double(Net::HTTP)
      allow(conn1).to receive(:started?).and_return(false)
      conn2 = instance_double(Net::HTTP)
      allow(conn2).to receive(:started?).and_return(false)

      pool.checkin(uri, conn1)
      pool.checkin(URI.parse('https://other.example.com/'), conn2)

      expect(pool.idle_count).to eq(2)
    end
  end

  describe 'idle timeout expiry' do
    it 'expires connections that exceed idle_timeout' do
      short_pool = described_class.new(size: 5, idle_timeout: 0)

      conn = instance_double(Net::HTTP)
      allow(conn).to receive(:started?).and_return(true)
      allow(conn).to receive(:finish)

      short_pool.checkin(uri, conn)
      # With idle_timeout 0, connection should be expired immediately on next checkout
      result = short_pool.checkout(uri)

      expect(result).to be_nil
      expect(conn).to have_received(:finish)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent checkout and checkin without errors' do
      threads = 10.times.map do
        Thread.new do
          conn = instance_double(Net::HTTP)
          allow(conn).to receive(:started?).and_return(false)
          pool.checkin(uri, conn)
          pool.checkout(uri)
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end
  end
end
