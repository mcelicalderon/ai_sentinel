# frozen_string_literal: true

RSpec.describe AiSentinel::Step do
  describe '#initialize' do
    it 'creates a step with name, action, and params' do
      step = described_class.new(name: :fetch, action: :http_get, url: 'https://example.com')

      expect(step.name).to eq(:fetch)
      expect(step.action).to eq(:http_get)
      expect(step.params[:url]).to eq('https://example.com')
    end

    it 'stores a condition lambda' do
      condition = ->(ctx) { ctx[:fetch]&.status == 200 }
      step = described_class.new(name: :notify, action: :http_post, condition: condition, url: 'https://hooks.example.com')

      expect(step.condition).to eq(condition)
    end
  end

  describe '#skip?' do
    it 'returns false when no condition is set' do
      step = described_class.new(name: :fetch, action: :http_get, url: 'https://example.com')
      context = instance_double(AiSentinel::Context)

      expect(step.skip?(context)).to be false
    end

    it 'returns false when condition is met' do
      step = described_class.new(name: :notify, action: :http_post, condition: ->(_ctx) { true }, url: 'https://example.com')
      context = instance_double(AiSentinel::Context)

      expect(step.skip?(context)).to be false
    end

    it 'returns true when condition is not met' do
      step = described_class.new(name: :notify, action: :http_post, condition: ->(_ctx) { false }, url: 'https://example.com')
      context = instance_double(AiSentinel::Context)

      expect(step.skip?(context)).to be true
    end
  end
end
