# frozen_string_literal: true

RSpec.describe AiSentinel::Persistence::ExecutionLog, :db do
  describe '.create' do
    it 'creates an execution log entry' do
      id = described_class.create(workflow_name: 'test_workflow')

      expect(id).to be_a(Integer)

      entry = AiSentinel::Persistence::Database.db[:execution_logs].where(id: id).first
      expect(entry[:workflow_name]).to eq('test_workflow')
      expect(entry[:status]).to eq('running')
    end
  end

  describe '.complete' do
    it 'marks an execution as completed' do
      id = described_class.create(workflow_name: 'test_workflow')
      described_class.complete(id)

      entry = AiSentinel::Persistence::Database.db[:execution_logs].where(id: id).first
      expect(entry[:status]).to eq('completed')
      expect(entry[:finished_at]).not_to be_nil
    end
  end

  describe '.fail' do
    it 'marks an execution as failed with error message' do
      id = described_class.create(workflow_name: 'test_workflow')
      described_class.fail(id, 'Something went wrong')

      entry = AiSentinel::Persistence::Database.db[:execution_logs].where(id: id).first
      expect(entry[:status]).to eq('failed')
      expect(entry[:error_message]).to eq('Something went wrong')
    end
  end

  describe '.log_step' do
    it 'logs a step result' do
      execution_id = described_class.create(workflow_name: 'test_workflow')
      described_class.log_step(
        execution_id: execution_id,
        step_name: :fetch,
        action: :http_get,
        status: 'completed',
        result_data: { status: 200, body: 'ok' },
        started_at: Time.now
      )

      steps = described_class.step_results(execution_id)
      expect(steps.size).to eq(1)
      expect(steps.first[:step_name]).to eq('fetch')
      expect(steps.first[:status]).to eq('completed')
    end
  end

  describe '.history' do
    it 'returns execution history' do
      described_class.create(workflow_name: 'workflow_a')
      described_class.create(workflow_name: 'workflow_b')

      history = described_class.history
      expect(history.size).to eq(2)
    end

    it 'filters by workflow name' do
      described_class.create(workflow_name: 'workflow_a')
      described_class.create(workflow_name: 'workflow_b')

      history = described_class.history(workflow_name: 'workflow_a')
      expect(history.size).to eq(1)
      expect(history.first[:workflow_name]).to eq('workflow_a')
    end

    it 'respects limit' do
      3.times { described_class.create(workflow_name: 'test') }

      history = described_class.history(limit: 2)
      expect(history.size).to eq(2)
    end
  end
end
