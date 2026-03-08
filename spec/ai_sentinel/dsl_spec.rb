# frozen_string_literal: true

RSpec.describe AiSentinel::DSL do
  describe '#build' do
    it 'builds a workflow from DSL block' do
      dsl = described_class.new('test_workflow') do
        schedule '0 9 * * *'
        step :fetch, action: :http_get, url: 'https://example.com'
      end

      workflow = dsl.build

      expect(workflow.name).to eq('test_workflow')
      expect(workflow.schedule_expression).to eq('0 9 * * *')
      expect(workflow.steps.size).to eq(1)
      expect(workflow.steps.first.name).to eq(:fetch)
    end

    it 'supports multiple steps' do
      dsl = described_class.new('multi') do
        schedule '*/5 * * * *'
        step :fetch, action: :http_get, url: 'https://example.com'
        step :analyze, action: :ai_prompt, prompt: 'Analyze: {{fetch.body}}'
        step :notify, action: :http_post, url: 'https://hooks.example.com', condition: ->(_ctx) { true }
      end

      workflow = dsl.build

      expect(workflow.steps.size).to eq(3)
      expect(workflow.steps.map(&:name)).to eq(%i[fetch analyze notify])
    end

    it 'raises when schedule is missing' do
      dsl = described_class.new('no_schedule') do
        step :fetch, action: :http_get, url: 'https://example.com'
      end

      expect { dsl.build }.to raise_error(AiSentinel::Error, /Schedule is required/)
    end

    it 'raises when no steps are defined' do
      dsl = described_class.new('no_steps') do
        schedule '0 9 * * *'
      end

      expect { dsl.build }.to raise_error(AiSentinel::Error, /At least one step is required/)
    end
  end
end
