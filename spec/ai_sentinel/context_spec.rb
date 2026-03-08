# frozen_string_literal: true

RSpec.describe AiSentinel::Context do
  subject(:context) { described_class.new(workflow_name: 'test', execution_id: 1) }

  describe '#set and #[]' do
    it 'stores and retrieves step results' do
      result = Struct.new(:body, :status, keyword_init: true).new(body: 'hello', status: 200)
      context.set(:fetch, result)

      expect(context[:fetch].body).to eq('hello')
      expect(context[:fetch].status).to eq(200)
    end

    it 'works with string keys' do
      context.set(:fetch, 'result')

      expect(context['fetch']).to eq('result')
    end
  end

  describe '#interpolate' do
    it 'replaces template variables with step results' do
      result = Struct.new(:body, :status, keyword_init: true).new(body: 'price data', status: 200)
      context.set(:fetch, result)

      output = context.interpolate('Analyze this: {{fetch.body}}')

      expect(output).to eq('Analyze this: price data')
    end

    it 'handles multiple variables' do
      fetch_result = Struct.new(:body, keyword_init: true).new(body: 'data')
      analyze_result = Struct.new(:response, keyword_init: true).new(response: 'analysis')
      context.set(:fetch, fetch_result)
      context.set(:analyze, analyze_result)

      output = context.interpolate('Data: {{fetch.body}}, Analysis: {{analyze.response}}')

      expect(output).to eq('Data: data, Analysis: analysis')
    end

    it 'leaves unresolvable templates intact' do
      output = context.interpolate('Missing: {{unknown.field}}')

      expect(output).to eq('Missing: {{unknown.field}}')
    end

    it 'returns non-string values unchanged' do
      expect(context.interpolate(42)).to eq(42)
    end
  end
end
