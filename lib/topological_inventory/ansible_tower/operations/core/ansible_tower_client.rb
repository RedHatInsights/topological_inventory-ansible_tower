require "topological_inventory/ansible_tower/logging"
require "topological_inventory/ansible_tower/connection"
require "topological_inventory/ansible_tower/operations/core/sources_api_client"
require "topological_inventory/ansible_tower/operations/core/topology_api_client"

module TopologicalInventory
  module AnsibleTower
    module Operations
      module Core
        class AnsibleTowerClient
          include Logging
          include Core::TopologyApiClient

          attr_accessor :connection_manager

          SLEEP_POLL = 10
          POLL_TIMEOUT = 1800

          def initialize(source_id, task_id, identity = nil)
            self.identity   = identity
            self.source_id  = source_id
            self.task_id    = task_id

            self.connection_manager = TopologicalInventory::AnsibleTower::Connection.new
          end

          # Format of order params (Input for Catalog - created by Collector, Output is produced by catalog - input of this worker)
          #
          # @example:
          #
          # * Input (ServicePlan.create_json_schema field)(created by lib/topological_inventory/ansible_tower/parser/service_plan.rb)
          #     {"schema":
          #       {"fields":[
          #         {"name":"providerControlParameters", ... },
          #         {"name":"NAMESPACE", "type":"text", ...},
          #         {"name":"MEMORY_LIMIT","type":"text","default":"512Mi","isRequired":true,...},
          #         {"name":"POSTGRESQL_USER",type":"text",...},
          #         ...
          #        ]
          #       },
          #      "defaultValues":{"NAMESPACE":"openshift","MEMORY_LIMIT":"512Mi","POSTGRESQL_USER":"","VOLUME_CAPACITY":"...}
          #     }
          #
          # * Output (== @param **order_params**):
          #
          #     { "NAMESPACE":"openshift",
          #       "MEMORY_LIMIT":"512Mi",
          #       "POSTGRESQL_USER":"",
          #       "providerControlParameters":{"namespace":"default"},
          #       ...
          #     }"
          def order_service_plan(job_type, job_template_id, order_params)
            job_template = if job_type == 'workflow_job_template'
                             ansible_tower.api.workflow_job_templates.find(job_template_id)
                           else
                             ansible_tower.api.job_templates.find(job_template_id)
                           end

            job = job_template.launch(job_values(order_params))

            # This means that api_client:job_template.launch() called job.find(nil), which returns list of jobs
            # => status error was returned, but api_client doesn't return errors
            raise ::AnsibleTowerClient::ResourceNotFoundError, "Job not found" if job.respond_to?(:count)

            job
          end

          def wait_for_job_finished(task_id, job, context)
            count = 0
            last_status = nil
            timeout_count = POLL_TIMEOUT / SLEEP_POLL
            loop do
              job = if job.type == 'workflow_job'
                      ansible_tower.api.workflow_jobs.find(job.id)
                    else
                      ansible_tower.api.jobs.find(job.id)
                    end

              if last_status != job.status
                last_status = job.status
                update_task(task_id, :state => "running", :status => job_status_to_task_status(job.status), :context => context.merge(:remote_status => job.status))
              end

              return job if job.finished.present?

              break if (count += 1) >= timeout_count

              sleep(SLEEP_POLL) # seconds
            end
            job
          end

          def job_status_to_task_status(job_status)
            case job_status
            when 'error', 'failed' then 'error'
            else 'ok'
            end
          end

          private

          attr_accessor :identity, :task_id, :source_id

          def job_values(order_parameters)
            if order_parameters["service_parameters"].blank?
              {}
            else
              { :extra_vars => order_parameters["service_parameters"] }
            end
          end

          def sources_api
            @sources_api ||= Core::SourcesApiClient.new(identity)
          end

          def default_endpoint
            @default_endpoint ||= sources_api.fetch_default_endpoint(source_id)
          end

          def authentication
            @authentication ||= sources_api.fetch_authentication(source_id, default_endpoint)
          end

          def verify_ssl_mode
            default_endpoint.verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
          end

          def ansible_tower
            @ansible_tower ||= connection_manager.connect(
              default_endpoint.host, authentication.username, authentication.password, :verify_ssl => verify_ssl_mode
            )
          end
        end
      end
    end
  end
end
