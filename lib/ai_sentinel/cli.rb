# frozen_string_literal: true

require 'thor'
require_relative 'cli/helpers'

module AiSentinel
  class CLI < Thor
    include Helpers

    class_option :config, type: :string, aliases: '-c', desc: 'Path to config file (default: ai_sentinel.yml)'

    desc 'start', 'Load workflows and start the scheduler'
    option :daemonize, type: :boolean, default: false, aliases: '-d', desc: 'Run in background'
    def start
      load_config
      AiSentinel.start(daemonize: options[:daemonize])
    end

    desc 'run WORKFLOW', 'Manually trigger a workflow immediately'
    def run_workflow(workflow_name)
      load_config
      AiSentinel.send(:resolve_api_key)
      AiSentinel.configuration.validate!
      Persistence::Database.setup(AiSentinel.configuration.database_path)

      scheduler = Scheduler.new(AiSentinel.registry, AiSentinel.configuration)
      context = scheduler.trigger(workflow_name)

      say "Workflow '#{workflow_name}' completed."
      context.results.each do |step_name, result|
        say "  #{step_name}: #{result_summary(result)}"
      end
    end
    map 'run' => :run_workflow

    desc 'validate', 'Validate the configuration file'
    def validate
      load_config
      AiSentinel.send(:resolve_api_key)
      AiSentinel.configuration.validate!
      say "Config is valid. #{AiSentinel.registry.size} workflow(s) loaded."
      AiSentinel.registry.each do |name, workflow|
        say "  #{name}: #{workflow.schedule_expression} (#{workflow.steps.size} steps)"
      end
    end

    desc 'list', 'List registered workflows'
    def list
      load_config

      if AiSentinel.registry.empty?
        say 'No workflows registered.'
        return
      end

      AiSentinel.registry.each do |name, workflow|
        say name.to_s
        say "  Schedule: #{workflow.schedule_expression}"
        say "  Steps:    #{workflow.steps.map(&:name).join(' -> ')}"
        say ''
      end
    end

    desc 'history [WORKFLOW]', 'Show execution history'
    option :limit, type: :numeric, default: 20, aliases: '-n', desc: 'Number of entries to show'
    option :db, type: :string, desc: 'Database path'
    def history(workflow_name = nil)
      setup_database
      entries = Persistence::ExecutionLog.history(workflow_name: workflow_name, limit: options[:limit])

      if entries.empty?
        say 'No execution history found.'
        return
      end

      entries.each do |entry|
        status_label = colorize_status(entry[:status])
        say "#{entry[:started_at].strftime('%Y-%m-%d %H:%M:%S')} | #{entry[:workflow_name].ljust(20)} | #{status_label}"

        next unless entry[:error_message]

        say "  Error: #{entry[:error_message]}"
      end
    end

    desc 'context WORKFLOW_NAME STEP_NAME', 'Show conversation context for a workflow step'
    option :db, type: :string, desc: 'Database path'
    option :limit, type: :numeric, default: 10, aliases: '-n', desc: 'Number of messages'
    def context(workflow_name, step_name)
      setup_database
      context_key = "#{workflow_name}:#{step_name}"
      messages = Persistence::Database.db[:conversation_messages]
                                      .where(context_key: context_key)
                                      .order(Sequel.desc(:created_at))
                                      .limit(options[:limit])
                                      .all
                                      .reverse

      if messages.empty?
        say "No conversation context found for #{context_key}."
        return
      end

      say "Conversation context for #{context_key} (#{messages.size} messages):"
      say ''
      messages.each do |msg|
        say "  [#{msg[:created_at].strftime('%Y-%m-%d %H:%M:%S')}]"
        say "  User:      #{truncate(msg[:user_message], 200)}"
        say "  Assistant: #{truncate(msg[:assistant_message], 200)}"
        say ''
      end
    end

    desc 'clear_context WORKFLOW_NAME STEP_NAME', 'Clear conversation context for a workflow step'
    option :db, type: :string, desc: 'Database path'
    def clear_context(workflow_name, step_name)
      setup_database
      context_key = "#{workflow_name}:#{step_name}"
      msg_count = Persistence::Database.db[:conversation_messages]
                                       .where(context_key: context_key)
                                       .delete
      sum_count = Persistence::Database.db[:context_summaries]
                                       .where(context_key: context_key)
                                       .delete

      say "Cleared #{msg_count} message(s) and #{sum_count} summary(ies) from context '#{context_key}'."
    end

    desc 'summary WORKFLOW_NAME STEP_NAME', 'Show the compacted context summary for a workflow step'
    option :db, type: :string, desc: 'Database path'
    def summary(workflow_name, step_name)
      setup_database
      display_summary("#{workflow_name}:#{step_name}")
    end

    desc 'init', 'Generate a sample ai_sentinel.yml config file'
    def init
      if File.exist?('ai_sentinel.yml')
        say 'ai_sentinel.yml already exists.'
        return
      end

      File.write('ai_sentinel.yml', sample_config)
      say 'Created ai_sentinel.yml with a sample workflow.'
    end

    desc 'version', 'Show AiSentinel version'
    def version
      say "ai_sentinel #{AiSentinel::VERSION}"
    end
    map '--version' => :version
    map '-v' => :version
  end
end
