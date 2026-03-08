# frozen_string_literal: true

require 'json'

module AiSentinel
  module Persistence
    class ExecutionLog
      class << self
        def create(workflow_name:)
          return nil unless Database.connected?

          now = Time.now
          Database.db[:execution_logs].insert(
            workflow_name: workflow_name,
            status: 'running',
            started_at: now,
            created_at: now,
            updated_at: now
          )
        end

        def complete(execution_id)
          return unless Database.connected? && execution_id

          now = Time.now
          Database.db[:execution_logs]
                  .where(id: execution_id)
                  .update(status: 'completed', finished_at: now, updated_at: now)
        end

        def fail(execution_id, error_message)
          return unless Database.connected? && execution_id

          now = Time.now
          Database.db[:execution_logs]
                  .where(id: execution_id)
                  .update(status: 'failed', finished_at: now, error_message: error_message, updated_at: now)
        end

        def log_step(execution_id:, step_name:, action:, status:, started_at:, result_data: nil, error_message: nil,
                     finished_at: nil)
          return unless Database.connected? && execution_id

          Database.db[:step_results].insert(
            execution_log_id: execution_id,
            step_name: step_name.to_s,
            action: action.to_s,
            status: status,
            result_data: result_data ? JSON.generate(serialize_result(result_data)) : nil,
            error_message: error_message,
            started_at: started_at,
            finished_at: finished_at || Time.now,
            created_at: Time.now
          )
        end

        def history(workflow_name: nil, limit: 20)
          return [] unless Database.connected?

          query = Database.db[:execution_logs].order(Sequel.desc(:started_at)).limit(limit)
          query = query.where(workflow_name: workflow_name) if workflow_name
          query.all
        end

        def step_results(execution_id)
          return [] unless Database.connected?

          Database.db[:step_results]
                  .where(execution_log_id: execution_id)
                  .order(:id)
                  .all
        end

        private

        def serialize_result(result)
          if result.respond_to?(:to_h)
            result.to_h
          elsif result.is_a?(Struct)
            result.members.zip(result.values).to_h
          else
            { value: result.to_s }
          end
        end
      end
    end
  end
end
