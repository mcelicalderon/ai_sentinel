# frozen_string_literal: true

RSpec.describe AiSentinel::Scheduler, :db do
  let(:configuration) do
    config = AiSentinel::Configuration.new
    config.api_key = 'test-key'
    config.logger = Logger.new(File::NULL)
    config
  end

  before { AiSentinel.instance_variable_set(:@configuration, configuration) }

  describe '#trigger' do
    it 'manually runs a workflow' do
      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 200, body: 'ok')

      workflow = AiSentinel::Workflow.new(
        name: 'test',
        schedule_expression: '0 9 * * *',
        steps: [
          AiSentinel::Step.new(name: :fetch, action: :http_get, url: 'https://api.example.com/data')
        ]
      )

      registry = { 'test' => workflow }
      scheduler = described_class.new(registry, configuration)
      context = scheduler.trigger('test')

      expect(context[:fetch].status).to eq(200)
    end

    it 'raises for unknown workflow' do
      scheduler = described_class.new({}, configuration)

      expect { scheduler.trigger('nonexistent') }.to raise_error(AiSentinel::Error, /Unknown workflow/)
    end
  end

  describe '#start' do
    it 'starts in daemonize mode without blocking' do
      workflow = AiSentinel::Workflow.new(
        name: 'test',
        schedule_expression: '0 9 * * *',
        steps: [
          AiSentinel::Step.new(name: :fetch, action: :http_get, url: 'https://api.example.com/data')
        ]
      )

      registry = { 'test' => workflow }
      scheduler = described_class.new(registry, configuration)
      scheduler.start(daemonize: true)
      scheduler.stop
    end
  end
end
