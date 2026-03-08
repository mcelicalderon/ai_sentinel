# frozen_string_literal: true

RSpec.describe AiSentinel do
  describe '.configure' do
    it 'yields the configuration' do
      described_class.configure do |config|
        config.api_key = 'test-key'
        config.model = 'claude-sonnet-4-20250514'
      end

      expect(described_class.configuration.api_key).to eq('test-key')
      expect(described_class.configuration.model).to eq('claude-sonnet-4-20250514')
    end

    it 'falls back to ANTHROPIC_API_KEY env var' do
      allow(ENV).to receive(:fetch).with('ANTHROPIC_API_KEY', nil).and_return('env-key')

      described_class.configure do |config|
        config.provider = :anthropic
      end

      expect(described_class.configuration.api_key).to eq('env-key')
    end
  end

  describe '.registry' do
    it 'stores workflows' do
      workflow = AiSentinel::Workflow.new(
        name: 'test',
        schedule_expression: '0 9 * * *',
        steps: [AiSentinel::Step.new(name: :fetch, action: :http_get, url: 'https://example.com')]
      )
      described_class.registry['test'] = workflow

      expect(described_class.registry).to have_key('test')
      expect(described_class.registry['test']).to be_a(AiSentinel::Workflow)
    end
  end

  describe '.reset!' do
    it 'clears configuration and registry' do
      described_class.configure { |c| c.api_key = 'test' }
      described_class.registry['test'] = AiSentinel::Workflow.new(
        name: 'test',
        schedule_expression: '0 9 * * *',
        steps: [AiSentinel::Step.new(name: :fetch, action: :http_get, url: 'https://example.com')]
      )

      described_class.reset!

      expect(described_class.registry).to be_empty
      expect(described_class.configuration.api_key).to be_nil
    end
  end

  describe 'VERSION' do
    it 'has a version number' do
      expect(AiSentinel::VERSION).not_to be_nil
    end
  end
end
