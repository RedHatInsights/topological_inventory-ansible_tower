require 'topological_inventory/providers/common/metrics'

module TopologicalInventory
  module AnsibleTower
    class Collector
      class Metrics < TopologicalInventory::Providers::Common::Metrics
        ERROR_TYPES = %i[general cloud receptor receptor_waiting receptor_timeout receptor_error_response].freeze

        def initialize(port = 9394)
          super(port)
        end

        def default_prefix
          "topological_inventory_ansible_tower_collector_"
        end
      end
    end
  end
end
