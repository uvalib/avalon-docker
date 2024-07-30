module Avalon
  module About
    class Redis < AboutPage::Configuration::Node
      render_with 'generic_hash'

      validates_each :status do |record, attr, value|
        record.errors.add attr, ": Can't connect to Redis" unless value
      end

      def initialize(redis)
        @redis = redis
      end

      def status
        @redis.ping == "PONG"
      rescue
        false
      end

      def to_h
        @redis.connection
      end
    end
  end
end