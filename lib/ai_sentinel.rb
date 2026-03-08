# frozen_string_literal: true

require 'zeitwerk'
require 'dotenv/load'
require 'logger'

require_relative 'ai_sentinel/version'

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  'cli' => 'CLI',
  'dsl' => 'DSL'
)
loader.ignore("#{__dir__}/ai_sentinel/version.rb")
loader.setup

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
