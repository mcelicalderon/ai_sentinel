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
  end
end
