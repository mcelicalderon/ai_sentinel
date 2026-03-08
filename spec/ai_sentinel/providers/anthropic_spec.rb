# frozen_string_literal: true

RSpec.describe AiSentinel::Providers::Anthropic, :db do
  let(:configuration) do
    config = AiSentinel::Configuration.new
    config.api_key = 'test-api-key'
    config.max_context_messages = 3
    config
  end

  describe '#chat' do
    it 'sends a request to the Anthropic API' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(
          status: 200,
          body: { content: [{ type: 'text', text: 'Hello!' }], model: 'claude-sonnet-4-20250514', usage: {} }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      provider = described_class.new(configuration: configuration)
      result = provider.chat(prompt: 'Hi', workflow_name: 'test', step_name: 'greet', remember: false)

      expect(result.response).to eq('Hello!')
    end

    it 'includes system prompt when provided' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .with(body: hash_including('system' => 'You are helpful'))
        .to_return(
          status: 200,
          body: { content: [{ type: 'text', text: 'OK' }], model: 'claude-sonnet-4-20250514', usage: {} }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      provider = described_class.new(configuration: configuration)
      provider.chat(prompt: 'Hi', system: 'You are helpful', workflow_name: 'test', step_name: 'greet', remember: false)
    end

    it 'raises on API error' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(
          status: 401,
          body: { error: { message: 'Invalid API key' } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      provider = described_class.new(configuration: configuration)

      expect do
        provider.chat(prompt: 'Hi', workflow_name: 'test', step_name: 'greet', remember: false)
      end.to raise_error(AiSentinel::Error, /Invalid API key/)
    end

    it 'prunes old context messages beyond max_context_messages' do
      4.times do |i|
        AiSentinel::Persistence::Database.db[:conversation_messages].insert(
          context_key: 'test:analyze',
          user_message: "Question #{i}",
          assistant_message: "Answer #{i}",
          created_at: Time.now + i,
          updated_at: Time.now + i
        )
      end

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(
          status: 200,
          body: { content: [{ type: 'text', text: 'New answer' }], model: 'claude-sonnet-4-20250514',
                  usage: {} }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      provider = described_class.new(configuration: configuration)
      provider.chat(prompt: 'New question', workflow_name: 'test', step_name: 'analyze')

      count = AiSentinel::Persistence::Database.db[:conversation_messages]
                                               .where(context_key: 'test:analyze')
                                               .count

      expect(count).to be <= configuration.max_context_messages
    end
  end
end
