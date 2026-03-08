# frozen_string_literal: true

RSpec.describe AiSentinel::Configuration do
  subject(:config) { described_class.new }

  describe 'defaults' do
    it 'sets provider to :anthropic' do
      expect(config.provider).to eq(:anthropic)
    end

    it 'sets model to claude-sonnet-4-20250514' do
      expect(config.model).to eq('claude-sonnet-4-20250514')
    end

    it 'sets database_path to home directory' do
      expect(config.database_path).to include('.ai_sentinel/db.sqlite3')
    end

    it 'sets max_context_messages to 50' do
      expect(config.max_context_messages).to eq(50)
    end

    it 'sets a default logger' do
      expect(config.logger).to be_a(Logger)
    end

    it 'defaults log_file to nil (STDOUT)' do
      expect(config.log_file).to be_nil
    end

    it 'defaults log_file_size to 10 MB' do
      expect(config.log_file_size).to eq(10 * 1024 * 1024)
    end

    it 'defaults log_files to 5' do
      expect(config.log_files).to eq(5)
    end
  end

  describe '#validate!' do
    it 'raises when api_key is nil' do
      config.api_key = nil
      expect { config.validate! }.to raise_error(AiSentinel::ConfigurationError, /API key is required/)
    end

    it 'raises when api_key is empty' do
      config.api_key = ''
      expect { config.validate! }.to raise_error(AiSentinel::ConfigurationError, /API key is required/)
    end

    it 'raises when provider is invalid' do
      config.api_key = 'test-key'
      config.provider = :invalid
      expect { config.validate! }.to raise_error(AiSentinel::ConfigurationError, /Invalid provider/)
    end

    it 'does not raise with valid configuration' do
      config.api_key = 'test-key'
      config.provider = :anthropic
      expect { config.validate! }.not_to raise_error
    end

    it 'accepts openai as a valid provider' do
      config.api_key = 'test-key'
      config.provider = :openai
      expect { config.validate! }.not_to raise_error
    end
  end

  describe '#model' do
    it 'returns default model for anthropic' do
      expect(config.model).to eq('claude-sonnet-4-20250514')
    end

    it 'returns default model for openai' do
      config.provider = :openai
      expect(config.model).to eq('gpt-4o')
    end

    it 'returns custom model when set' do
      config.model = 'custom-model'
      expect(config.model).to eq('custom-model')
    end
  end

  describe '#env_key_name' do
    it 'returns ANTHROPIC_API_KEY for anthropic provider' do
      expect(config.env_key_name).to eq('ANTHROPIC_API_KEY')
    end

    it 'returns OPENAI_API_KEY for openai provider' do
      config.provider = :openai
      expect(config.env_key_name).to eq('OPENAI_API_KEY')
    end
  end

  describe '#base_url' do
    it 'returns default URL for anthropic' do
      expect(config.base_url).to eq('https://api.anthropic.com/v1/messages')
    end

    it 'returns default URL for openai' do
      config.provider = :openai
      expect(config.base_url).to eq('https://api.openai.com/v1/chat/completions')
    end

    it 'returns custom URL when set' do
      config.base_url = 'http://localhost:11434/v1/chat/completions'
      expect(config.base_url).to eq('http://localhost:11434/v1/chat/completions')
    end
  end

  describe '#logger' do
    it 'logs to STDOUT by default' do
      expect { config.logger.info('test') }.to output(/test/).to_stdout_from_any_process
    end

    it 'logs to a file when log_file is set' do
      Dir.mktmpdir do |tmpdir|
        log_path = File.join(tmpdir, 'test.log')
        config.log_file = log_path
        config.logger.info('hello from file')

        expect(File.read(log_path)).to include('hello from file')
      end
    end

    it 'creates the log directory if it does not exist' do
      Dir.mktmpdir do |tmpdir|
        log_path = File.join(tmpdir, 'nested', 'dir', 'test.log')
        config.log_file = log_path
        config.logger.info('nested log')

        expect(File.exist?(log_path)).to be true
      end
    end

    it 'configures rotation with log_files and log_file_size' do
      Dir.mktmpdir do |tmpdir|
        log_path = File.join(tmpdir, 'test.log')
        config.log_file = log_path
        config.log_file_size = 1024
        config.log_files = 3
        logger = config.logger

        expect(logger).to be_a(Logger)
      end
    end

    it 'returns a custom logger when set directly' do
      custom = Logger.new(File::NULL)
      config.logger = custom

      expect(config.logger).to be(custom)
    end
  end

  describe '#inspect' do
    it 'does not expose the api_key value' do
      config.api_key = 'sk-ant-super-secret-key'
      output = config.inspect

      expect(output).not_to include('sk-ant-super-secret-key')
      expect(output).to include('[FILTERED]')
    end

    it 'shows nil when api_key is not set' do
      output = config.inspect

      expect(output).to include('api_key=nil')
    end

    it 'includes non-sensitive configuration values' do
      output = config.inspect

      expect(output).to include('provider=anthropic')
      expect(output).to include('model=claude-sonnet-4-20250514')
    end

    it 'shows STDOUT when log_file is nil' do
      expect(config.inspect).to include('log_file=STDOUT')
    end

    it 'shows the log_file path when set' do
      config.log_file = '/var/log/ai_sentinel.log'
      expect(config.inspect).to include('log_file=/var/log/ai_sentinel.log')
    end
  end
end
