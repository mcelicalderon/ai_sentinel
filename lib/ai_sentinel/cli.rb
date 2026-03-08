# frozen_string_literal: true

require 'thor'

module AiSentinel
  class CLI < Thor
    desc 'start CONFIG_FILE', 'Load workflows from a Ruby config file and start the scheduler'
    option :daemonize, type: :boolean, default: false, aliases: '-d', desc: 'Run in background'
    def start(config_file)
      load_config(config_file)
      AiSentinel.start(daemonize: options[:daemonize])
    end

    desc 'run CONFIG_FILE WORKFLOW', 'Manually trigger a workflow immediately'
    def run_workflow(config_file, workflow_name)
      load_config(config_file)
      AiSentinel.configuration.api_key ||= ENV.fetch('ANTHROPIC_API_KEY', nil)
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

    desc 'list CONFIG_FILE', 'List registered workflows'
    def list(config_file)
      load_config(config_file)

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
      db_path = options[:db] || AiSentinel.configuration.database_path
      Persistence::Database.setup(db_path)

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
      db_path = options[:db] || AiSentinel.configuration.database_path
      Persistence::Database.setup(db_path)

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
      db_path = options[:db] || AiSentinel.configuration.database_path
      Persistence::Database.setup(db_path)

      context_key = "#{workflow_name}:#{step_name}"
      count = Persistence::Database.db[:conversation_messages]
                                   .where(context_key: context_key)
                                   .delete

      say "Cleared #{count} message(s) from context '#{context_key}'."
    end

    desc 'version', 'Show AiSentinel version'
    def version
      say "ai_sentinel #{AiSentinel::VERSION}"
    end

    private

    def load_config(config_file)
      path = File.expand_path(config_file)
      raise Error, "Config file not found: #{path}" unless File.exist?(path)

      load(path)
    end

    def result_summary(result)
      case result
      when Actions::AiPrompt::Result
        truncate(result.response, 100)
      when Actions::HttpGet::Result, Actions::HttpPost::Result
        "HTTP #{result.status} (#{result.body.length} bytes)"
      when Actions::ShellCommand::Result
        result.success ? 'exit 0' : "exit #{result.exit_code}"
      else
        result.to_s[0..100]
      end
    end

    def truncate(text, length)
      return text if text.length <= length

      "#{text[0...length]}..."
    end

    def colorize_status(status)
      case status
      when 'completed' then "\e[32m#{status}\e[0m"
      when 'failed'    then "\e[31m#{status}\e[0m"
      when 'running'   then "\e[33m#{status}\e[0m"
      else status
      end
    end
  end
end
