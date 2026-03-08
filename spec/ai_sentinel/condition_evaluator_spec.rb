# frozen_string_literal: true

RSpec.describe AiSentinel::ConditionEvaluator do
  let(:context) { AiSentinel::Context.new(workflow_name: 'test', execution_id: 1) }

  before do
    fetch_result = Struct.new(:status, :body, keyword_init: true).new(status: 200, body: 'anomaly detected')
    context.set(:fetch, fetch_result)
  end

  describe '.evaluate' do
    it 'evaluates equality with ==' do
      expect(described_class.evaluate('{{fetch.status}} == 200', context)).to be true
      expect(described_class.evaluate('{{fetch.status}} == 404', context)).to be false
    end

    it 'evaluates inequality with !=' do
      expect(described_class.evaluate('{{fetch.status}} != 404', context)).to be true
      expect(described_class.evaluate('{{fetch.status}} != 200', context)).to be false
    end

    it 'evaluates greater than' do
      expect(described_class.evaluate('{{fetch.status}} > 100', context)).to be true
      expect(described_class.evaluate('{{fetch.status}} > 300', context)).to be false
    end

    it 'evaluates less than' do
      expect(described_class.evaluate('{{fetch.status}} < 300', context)).to be true
      expect(described_class.evaluate('{{fetch.status}} < 100', context)).to be false
    end

    it 'evaluates contains' do
      expect(described_class.evaluate('{{fetch.body}} contains "anomaly"', context)).to be true
      expect(described_class.evaluate('{{fetch.body}} contains "normal"', context)).to be false
    end

    it 'evaluates not_contains' do
      expect(described_class.evaluate('{{fetch.body}} not_contains "normal"', context)).to be true
      expect(described_class.evaluate('{{fetch.body}} not_contains "anomaly"', context)).to be false
    end

    it 'evaluates truthiness for non-comparison expressions' do
      expect(described_class.evaluate('{{fetch.body}}', context)).to be true
      expect(described_class.evaluate('{{missing.field}}', context)).to be false
    end

    it 'handles quoted strings on the right side' do
      expect(described_class.evaluate("{{fetch.body}} contains 'anomaly'", context)).to be true
    end
  end
end
