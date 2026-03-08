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
end
