# frozen_string_literal: true

RSpec.describe AiSentinel::Actions::HttpPost do
  let(:configuration) { AiSentinel::Configuration.new }
  let(:context) { AiSentinel::Context.new(workflow_name: 'test', execution_id: 1) }

  before do
    allow(Resolv).to receive(:getaddresses).and_return(['93.184.216.34'])
  end

  describe '#call' do
    it 'makes an HTTP POST request with JSON body' do
      step = AiSentinel::Step.new(
        name: :notify, action: :http_post,
        url: 'https://hooks.example.com/webhook',
        body: { text: 'Alert!' }
      )

      stub_request(:post, 'https://hooks.example.com/webhook')
        .with(
          body: '{"text":"Alert!"}',
          headers: { 'Content-Type' => 'application/json' }
        )
        .to_return(status: 200, body: 'ok')

      action = described_class.new(step: step, context: context, configuration: configuration)
      result = action.call

      expect(result.status).to eq(200)
    end

    it 'interpolates template variables in body values' do
      analyze_result = Struct.new(:response, keyword_init: true).new(response: 'Found anomaly in prices')
      context.set(:analyze, analyze_result)

      step = AiSentinel::Step.new(
        name: :notify, action: :http_post,
        url: 'https://hooks.example.com/webhook',
        body: { text: '{{analyze.response}}' }
      )

      stub_request(:post, 'https://hooks.example.com/webhook')
        .with(body: '{"text":"Found anomaly in prices"}')
        .to_return(status: 200, body: 'ok')

      action = described_class.new(step: step, context: context, configuration: configuration)
      result = action.call

      expect(result.status).to eq(200)
    end

    it 'supports string payload' do
      step = AiSentinel::Step.new(
        name: :notify, action: :http_post,
        url: 'https://hooks.example.com/webhook',
        body: 'raw payload'
      )

      stub_request(:post, 'https://hooks.example.com/webhook')
        .with(body: 'raw payload')
        .to_return(status: 200, body: 'ok')

      action = described_class.new(step: step, context: context, configuration: configuration)
      result = action.call

      expect(result.status).to eq(200)
    end

    it 'rejects requests to private IP addresses' do
      allow(Resolv).to receive(:getaddresses).and_return(['10.0.0.1'])

      step = AiSentinel::Step.new(
        name: :notify, action: :http_post,
        url: 'https://internal.example.com/webhook',
        body: { text: 'test' }
      )
      action = described_class.new(step: step, context: context, configuration: configuration)

      expect { action.call }.to raise_error(AiSentinel::Error, %r{private/internal address})
    end
  end
end
