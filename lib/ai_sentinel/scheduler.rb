# frozen_string_literal: true

require 'dotenv'
require 'fileutils'
require 'rufus-scheduler'

module AiSentinel
  class Scheduler
    attr_reader :registry, :configuration, :rufus

    def initialize(registry, configuration)
      @registry = registry
      @configuration = configuration
    end

    def start(daemonize: false)
      apply_working_directory

      if daemonize
        Persistence::Database.disconnect
        Process.daemon(true, true)
        Persistence::Database.setup(configuration.database_path)
        write_pid_file
        setup_crash_cleanup
        AiSentinel.logger.info("AiSentinel started in background (PID #{Process.pid}, #{registry.size} workflow(s))")
      else
        AiSentinel.logger.info("AiSentinel started (#{registry.size} workflow(s)). Press Ctrl+C to stop.")
      end

      @rufus = Rufus::Scheduler.new
      register_workflows

      trap('INT') { Thread.new { stop } }
      trap('TERM') { Thread.new { stop } }
      @rufus.join
      cleanup_pid_file
      AiSentinel.logger.info('AiSentinel stopped')
    rescue StandardError => e
      AiSentinel.log_error(e, context: 'Scheduler crashed')
      cleanup_pid_file
      raise
    end

    def stop
      @rufus&.shutdown
    rescue StandardError => e
      AiSentinel.log_error(e, context: 'Error during shutdown')
    end

    def trigger(workflow_name)
      apply_working_directory

      workflow = registry[workflow_name.to_s] || registry[workflow_name.to_sym]
      raise Error, "Unknown workflow: #{workflow_name}" unless workflow

      runner = Runner.new(workflow: workflow, configuration: configuration)
      runner.execute
    end

    def pid_file
      @pid_file ||= configuration.pid_file
    end

    private

    def apply_working_directory
      dir = configuration.working_directory
      return unless dir

      FileUtils.mkdir_p(dir)
      Dir.chdir(dir)
      Dotenv.load
    end

    def write_pid_file
      FileUtils.mkdir_p(File.dirname(pid_file))
      File.write(pid_file, Process.pid.to_s)
    end

    def cleanup_pid_file
      FileUtils.rm_f(pid_file)
    end

    def setup_crash_cleanup
      at_exit { cleanup_pid_file }
    end

    def register_workflows
      registry.each do |name, workflow|
        @rufus.cron(workflow.schedule_expression) do
          runner = Runner.new(workflow: workflow, configuration: configuration)
          runner.execute
        rescue StandardError => e
          AiSentinel.log_error(e, context: "Workflow '#{name}' failed")
        end

        AiSentinel.logger.info("Registered workflow '#{name}' with schedule '#{workflow.schedule_expression}'")
      end
    end
  end
end
