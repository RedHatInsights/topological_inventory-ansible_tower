require 'topological_inventory/providers/common/metrics'

module TopologicalInventory
  module AnsibleTower
    module Operations
      class Metrics < TopologicalInventory::Providers::Common::Metrics
        def initialize(port = 9394)
          super(port)
        end

        def default_prefix
          "topological_inventory_ansible_tower_operations_"
        end
      end
    end
  end
end
