# frozen_string_literal: true

require 'fileutils'

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

    DEFAULT_LOG_FILE_SIZE = 10 * 1024 * 1024
    DEFAULT_LOG_FILES = 5

    attr_accessor :provider, :api_key, :database_path, :max_context_messages,
                  :compaction_threshold, :compaction_buffer, :log_file,
                  :log_file_size, :log_files
    attr_writer :model, :base_url, :logger

    def initialize
      @provider = :anthropic
      @api_key = nil
      @model = nil
      @base_url = nil
      @database_path = File.join(Dir.home, '.ai_sentinel', 'db.sqlite3')
      @logger = nil
      @log_file = nil
      @log_file_size = DEFAULT_LOG_FILE_SIZE
      @log_files = DEFAULT_LOG_FILES
      @max_context_messages = 50
      @compaction_threshold = 40
      @compaction_buffer = 10
    end

    def logger
      @logger ||= build_logger
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

    def inspect
      "#<#{self.class} provider=#{provider} model=#{model} base_url=#{base_url} " \
        "database_path=#{database_path} log_file=#{log_file || 'STDOUT'} " \
        "max_context_messages=#{max_context_messages} " \
        "compaction_threshold=#{compaction_threshold} compaction_buffer=#{compaction_buffer} " \
        "api_key=#{api_key ? '[FILTERED]' : 'nil'}>"
    end
    alias to_s inspect

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

    def build_logger
      output = if log_file
                 ensure_log_directory(log_file)
                 Logger.new(log_file, log_files, log_file_size)
               else
                 Logger.new($stdout)
               end
      output.level = Logger::INFO
      output.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
      end
      output
    end

    def ensure_log_directory(path)
      dir = File.dirname(File.expand_path(path))
      FileUtils.mkdir_p(dir)
    end
  end
end
