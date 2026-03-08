# frozen_string_literal: true

RSpec.describe AiSentinel::Runner, :db do
  let(:configuration) do
    config = AiSentinel::Configuration.new
    config.api_key = 'test-key'
    config.logger = Logger.new(File::NULL)
    config
  end

  before do
    AiSentinel.instance_variable_set(:@configuration, configuration)
    allow(Resolv).to receive(:getaddresses).and_return(['93.184.216.34'])
  end

  describe '#execute' do
    it 'runs all steps in a workflow' do
      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 200, body: 'response data')

      stub_request(:post, 'https://hooks.example.com/notify')
        .to_return(status: 200, body: 'ok')

      workflow = AiSentinel::Workflow.new(
        name: 'test',
        schedule_expression: '0 9 * * *',
        steps: [
          AiSentinel::Step.new(name: :fetch, action: :http_get, url: 'https://api.example.com/data'),
          AiSentinel::Step.new(name: :notify, action: :http_post, url: 'https://hooks.example.com/notify',
                               body: { data: '{{fetch.body}}' })
        ]
      )

      runner = described_class.new(workflow: workflow, configuration: configuration)
      context = runner.execute

      expect(context[:fetch].status).to eq(200)
      expect(context[:notify].status).to eq(200)
    end

    it 'skips steps whose condition returns false' do
      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 200, body: 'ok')

      workflow = AiSentinel::Workflow.new(
        name: 'test',
        schedule_expression: '0 9 * * *',
        steps: [
          AiSentinel::Step.new(name: :fetch, action: :http_get, url: 'https://api.example.com/data'),
          AiSentinel::Step.new(name: :notify, action: :http_post, url: 'https://hooks.example.com/notify',
                               condition: ->(_ctx) { false })
        ]
      )

      runner = described_class.new(workflow: workflow, configuration: configuration)
      context = runner.execute

      expect(context[:fetch]).not_to be_nil
      expect(context[:notify]).to be_nil
    end

    it 'logs execution to database' do
      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 200, body: 'ok')

      workflow = AiSentinel::Workflow.new(
        name: 'test',
        schedule_expression: '0 9 * * *',
        steps: [
          AiSentinel::Step.new(name: :fetch, action: :http_get, url: 'https://api.example.com/data')
        ]
      )

      runner = described_class.new(workflow: workflow, configuration: configuration)
      runner.execute

      history = AiSentinel::Persistence::ExecutionLog.history(workflow_name: 'test')
      expect(history.size).to eq(1)
      expect(history.first[:status]).to eq('completed')
    end

    it 'marks execution as failed on error' do
      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 500, body: 'error')

      workflow = AiSentinel::Workflow.new(
        name: 'test',
        schedule_expression: '0 9 * * *',
        steps: [
          AiSentinel::Step.new(name: :fetch, action: :http_get, url: 'https://api.example.com/data'),
          AiSentinel::Step.new(name: :process, action: :shell_command, command: 'nonexistent_command_xyz')
        ]
      )

      runner = described_class.new(workflow: workflow, configuration: configuration)

      expect { runner.execute }.to raise_error(StandardError)

      history = AiSentinel::Persistence::ExecutionLog.history(workflow_name: 'test')
      expect(history.first[:status]).to eq('failed')
    end

    it 'raises on unknown action' do
      workflow = AiSentinel::Workflow.new(
        name: 'test',
        schedule_expression: '0 9 * * *',
        steps: [
          AiSentinel::Step.new(name: :bad, action: :nonexistent)
        ]
      )

      runner = described_class.new(workflow: workflow, configuration: configuration)

      expect { runner.execute }.to raise_error(AiSentinel::Error, /Unknown action/)
    end
  end
end
