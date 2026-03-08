# frozen_string_literal: true

module AiSentinel
  class Configuration
    VALID_PROVIDERS = %i[anthropic].freeze

    attr_accessor :provider, :api_key, :model, :database_path, :logger, :max_context_messages

    def initialize
      @provider = :anthropic
      @api_key = nil
      @model = 'claude-sonnet-4-20250514'
      @database_path = File.join(Dir.home, '.ai_sentinel', 'db.sqlite3')
      @logger = default_logger
      @max_context_messages = 50
    end

    def validate!
      if api_key.nil? || api_key.empty?
        raise ConfigurationError,
              'API key is required. Set it via AiSentinel.configure or ANTHROPIC_API_KEY env var'
      end
      return if VALID_PROVIDERS.include?(provider)

      raise ConfigurationError,
            "Invalid provider: #{provider}. Valid: #{VALID_PROVIDERS.join(', ')}"
    end

    private

    def default_logger
      logger = Logger.new($stdout)
      logger.level = Logger::INFO
      logger.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
      end
      logger
    end
  end
end
