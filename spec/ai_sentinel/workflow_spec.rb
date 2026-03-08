# frozen_string_literal: true

RSpec.describe AiSentinel::Workflow do
  describe '#initialize' do
    it 'creates a workflow with name, schedule, and steps' do
      step = AiSentinel::Step.new(name: :fetch, action: :http_get, url: 'https://example.com')
      workflow = described_class.new(name: 'test', schedule_expression: '0 9 * * *', steps: [step])

      expect(workflow.name).to eq('test')
      expect(workflow.schedule_expression).to eq('0 9 * * *')
      expect(workflow.steps.size).to eq(1)
    end
  end

  describe '#add_step' do
    it 'appends a step to the workflow' do
      workflow = described_class.new(name: 'test', schedule_expression: '0 9 * * *')
      step = AiSentinel::Step.new(name: :fetch, action: :http_get, url: 'https://example.com')

      workflow.add_step(step)

      expect(workflow.steps.size).to eq(1)
      expect(workflow.steps.first.name).to eq(:fetch)
    end
  end
end
