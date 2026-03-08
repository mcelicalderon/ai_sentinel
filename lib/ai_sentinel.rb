# frozen_string_literal: true

require 'dotenv/load'
require 'logger'

require_relative 'ai_sentinel/version'
require_relative 'ai_sentinel/configuration'
require_relative 'ai_sentinel/context'
require_relative 'ai_sentinel/step'
require_relative 'ai_sentinel/workflow'
require_relative 'ai_sentinel/dsl'
require_relative 'ai_sentinel/actions/base'
require_relative 'ai_sentinel/actions/http_get'
require_relative 'ai_sentinel/actions/http_post'
require_relative 'ai_sentinel/actions/ai_prompt'
require_relative 'ai_sentinel/actions/shell_command'
require_relative 'ai_sentinel/providers/base'
require_relative 'ai_sentinel/providers/anthropic'
require_relative 'ai_sentinel/persistence/database'
require_relative 'ai_sentinel/persistence/execution_log'
require_relative 'ai_sentinel/runner'
require_relative 'ai_sentinel/scheduler'
require_relative 'ai_sentinel/cli'

module AiSentinel
  class Error < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
      configuration.api_key ||= ENV.fetch('ANTHROPIC_API_KEY', nil)
      configuration
    end

    def watch(name, &)
      workflow = DSL.new(name, &).build
      registry[name] = workflow
      workflow
    end

    def registry
      @registry ||= {}
    end

    def start(daemonize: false)
      configuration.api_key ||= ENV.fetch('ANTHROPIC_API_KEY', nil)
      configuration.validate!
      Persistence::Database.setup(configuration.database_path)
      scheduler = Scheduler.new(registry, configuration)
      scheduler.start(daemonize: daemonize)
      scheduler
    end

    def reset!
      @configuration = nil
      @registry = {}
    end

    def logger
      configuration.logger
    end
  end
end
