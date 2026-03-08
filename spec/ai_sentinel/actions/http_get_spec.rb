# frozen_string_literal: true

RSpec.describe AiSentinel::Actions::HttpGet do
  let(:configuration) { AiSentinel::Configuration.new }
  let(:context) { AiSentinel::Context.new(workflow_name: 'test', execution_id: 1) }
  let(:step) { AiSentinel::Step.new(name: :fetch, action: :http_get, url: 'https://api.example.com/data') }

  before do
    allow(Resolv).to receive(:getaddresses).and_return(['93.184.216.34'])
  end

  describe '#call' do
    it 'makes an HTTP GET request and returns a result' do
      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 200, body: '{"prices": [1, 2, 3]}', headers: { 'Content-Type' => 'application/json' })

      action = described_class.new(step: step, context: context, configuration: configuration)
      result = action.call

      expect(result.status).to eq(200)
      expect(result.body).to eq('{"prices": [1, 2, 3]}')
      expect(result.headers['content-type']).to eq('application/json')
    end

    it 'interpolates template variables in URL' do
      prev_result = Struct.new(:id, keyword_init: true).new(id: '42')
      context.set(:lookup, prev_result)

      step_with_template = AiSentinel::Step.new(name: :fetch, action: :http_get, url: 'https://api.example.com/items/{{lookup.id}}')

      stub_request(:get, 'https://api.example.com/items/42')
        .to_return(status: 200, body: 'ok')

      action = described_class.new(step: step_with_template, context: context, configuration: configuration)
      result = action.call

      expect(result.status).to eq(200)
    end

    it 'passes custom headers' do
      step_with_headers = AiSentinel::Step.new(
        name: :fetch, action: :http_get,
        url: 'https://api.example.com/data',
        headers: { 'Authorization' => 'Bearer token123' }
      )

      stub_request(:get, 'https://api.example.com/data')
        .with(headers: { 'Authorization' => 'Bearer token123' })
        .to_return(status: 200, body: 'ok')

      action = described_class.new(step: step_with_headers, context: context, configuration: configuration)
      result = action.call

      expect(result.status).to eq(200)
    end

    it 'rejects requests to private IP addresses' do
      allow(Resolv).to receive(:getaddresses).and_return(['192.168.1.1'])

      step = AiSentinel::Step.new(name: :fetch, action: :http_get, url: 'https://internal.example.com/data')
      action = described_class.new(step: step, context: context, configuration: configuration)

      expect { action.call }.to raise_error(AiSentinel::Error, %r{private/internal address})
    end

    it 'rejects requests to loopback addresses' do
      allow(Resolv).to receive(:getaddresses).and_return(['127.0.0.1'])

      step = AiSentinel::Step.new(name: :fetch, action: :http_get, url: 'https://localhost/data')
      action = described_class.new(step: step, context: context, configuration: configuration)

      expect { action.call }.to raise_error(AiSentinel::Error, %r{private/internal address})
    end
  end
end
