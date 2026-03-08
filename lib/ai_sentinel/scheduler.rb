# frozen_string_literal: true

require 'rufus-scheduler'

module AiSentinel
  class Scheduler
    attr_reader :registry, :configuration, :rufus

    def initialize(registry, configuration)
      @registry = registry
      @configuration = configuration
      @rufus = Rufus::Scheduler.new
    end

    def start(daemonize: false)
      register_workflows

      if daemonize
        AiSentinel.logger.info("AiSentinel started in background (#{registry.size} workflow(s))")
      else
        AiSentinel.logger.info("AiSentinel started (#{registry.size} workflow(s)). Press Ctrl+C to stop.")
        @rufus.join
      end
    end

    def stop
      @rufus.shutdown
      AiSentinel.logger.info('AiSentinel stopped')
    end

    def trigger(workflow_name)
      workflow = registry[workflow_name.to_s] || registry[workflow_name.to_sym]
      raise Error, "Unknown workflow: #{workflow_name}" unless workflow

      runner = Runner.new(workflow: workflow, configuration: configuration)
      runner.execute
    end

    private

    def register_workflows
      registry.each do |name, workflow|
        @rufus.cron(workflow.schedule_expression) do
          runner = Runner.new(workflow: workflow, configuration: configuration)
          runner.execute
        rescue StandardError => e
          AiSentinel.logger.error("Workflow '#{name}' failed: #{e.message}")
        end

        AiSentinel.logger.info("Registered workflow '#{name}' with schedule '#{workflow.schedule_expression}'")
      end
    end
  end
end
