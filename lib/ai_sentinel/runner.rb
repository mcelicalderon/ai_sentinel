# frozen_string_literal: true

module AiSentinel
  class Runner
    ACTION_MAP = {
      http_get: Actions::HttpGet,
      http_post: Actions::HttpPost,
      ai_prompt: Actions::AiPrompt,
      shell_command: Actions::ShellCommand
    }.freeze

    attr_reader :workflow, :configuration

    def initialize(workflow:, configuration:)
      @workflow = workflow
      @configuration = configuration
    end

    def execute
      execution_id = Persistence::ExecutionLog.create(workflow_name: workflow.name)
      context = Context.new(workflow_name: workflow.name, execution_id: execution_id)

      AiSentinel.logger.info("Starting workflow '#{workflow.name}'")

      workflow.steps.each do |step|
        execute_step(step, context)
      end

      Persistence::ExecutionLog.complete(execution_id)
      AiSentinel.logger.info("Workflow '#{workflow.name}' completed successfully")
      context
    rescue StandardError => e
      Persistence::ExecutionLog.fail(execution_id, e.message)
      AiSentinel.log_error(e, context: "Workflow '#{workflow.name}' failed")
      raise
    end

    private

    def execute_step(step, context)
      if step.skip?(context)
        AiSentinel.logger.info("  Skipping step '#{step.name}' (condition not met)")
        return
      end

      AiSentinel.logger.info("  Running step '#{step.name}' (#{step.action})")
      started_at = Time.now
      result = run_action(step, context)
      context.set(step.name, result)

      log_step_result(context, step, 'completed', started_at, result_data: result)
      AiSentinel.logger.info("  Step '#{step.name}' completed")
    rescue StandardError => e
      log_step_result(context, step, 'failed', started_at || Time.now, error_message: e.message)
      raise
    end

    def run_action(step, context)
      action_class = ACTION_MAP[step.action]
      raise Error, "Unknown action: #{step.action}" unless action_class

      action_class.new(step: step, context: context, configuration: configuration).call
    end

    def log_step_result(context, step, status, started_at, result_data: nil, error_message: nil)
      Persistence::ExecutionLog.log_step(
        execution_id: context.execution_id,
        step_name: step.name,
        action: step.action,
        status: status,
        result_data: result_data,
        error_message: error_message,
        started_at: started_at
      )
    end
  end
end
