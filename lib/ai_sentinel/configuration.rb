# frozen_string_literal: true

module AiSentinel
  class Configuration
    VALID_PROVIDERS = %i[anthropic openai].freeze

    DEFAULT_MODELS = {
      anthropic: 'claude-sonnet-4-20250514',
      openai: 'gpt-4o'
    }.freeze

    ENV_KEY_MAP = {
      anthropic: 'ANTHROPIC_API_KEY',
      openai: 'OPENAI_API_KEY'
    }.freeze

    DEFAULT_URLS = {
      anthropic: 'https://api.anthropic.com/v1/messages',
      openai: 'https://api.openai.com/v1/chat/completions'
    }.freeze

    attr_accessor :provider, :api_key, :database_path, :logger, :max_context_messages
    attr_writer :model, :base_url

    def initialize
      @provider = :anthropic
      @api_key = nil
      @model = nil
      @base_url = nil
      @database_path = File.join(Dir.home, '.ai_sentinel', 'db.sqlite3')
      @logger = default_logger
      @max_context_messages = 50
    end

    def model
      @model || DEFAULT_MODELS[provider]
    end

    def base_url
      @base_url || DEFAULT_URLS[provider]
    end

    def env_key_name
      ENV_KEY_MAP[provider]
    end

    def validate!
      if api_key.nil? || api_key.empty?
        raise ConfigurationError,
              "API key is required. Set it via AiSentinel.configure or #{env_key_name} env var"
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
