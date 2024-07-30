module Avalon
  module About
    class Sidekiq < AboutPage::Configuration::Node
      render_with 'generic_hash'

      validates_each :status do |record, attr, value|
        record.errors.add attr, ": Sidekiq process count does not match #{@process_count}" unless value
      end

      def initialize(numProcesses: 1)
        @process_count = numProcesses
      end

      def status
        ::Sidekiq::ProcessSet.new.size == @process_count
      rescue
        false
      end

      def to_h
        ::Sidekiq::ProcessSet.new.as_json.first['attribs']
      end
    end
  end
end