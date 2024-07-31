# Copyright 2011-2013, The Trustees of Indiana University and Northwestern
#   University.  Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed
#   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
#   CONDITIONS OF ANY KIND, either express or implied. See the License for the
#   specific language governing permissions and limitations under the License.
# ---  END LICENSE_HEADER BLOCK  ---

module Avalon
  module About
    class Database < AboutPage::Configuration::Node
      render_with 'generic_hash'

      validates_each :connected? do |record, attr, value|
        record.errors.add attr, " == false" unless value
      end

      def initialize(model=nil)
        @model = model || ActiveRecord::Base.descendants.first
      end

      def connected?
        @model.count
        @model.connected?
      rescue
        false
      end

      def to_h
        result = @model.connection_db_config.configuration_hash.reject { |k,v| [:username,:password].include?(k) }
        result['connected'] = connected?
        result
      end
    end
  end
end