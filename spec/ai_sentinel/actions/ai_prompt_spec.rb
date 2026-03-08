# frozen_string_literal: true

RSpec.describe AiSentinel::Actions::AiPrompt, :db do
  let(:configuration) do
    config = AiSentinel::Configuration.new
    config.api_key = 'test-api-key'
    config
  end
  let(:context) { AiSentinel::Context.new(workflow_name: 'test_workflow', execution_id: 1) }

  describe '#call' do
    it 'sends a prompt to the Anthropic API and returns the response' do
      step = AiSentinel::Step.new(name: :analyze, action: :ai_prompt, prompt: 'What is 2+2?')

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .with(
          headers: { 'x-api-key' => 'test-api-key', 'anthropic-version' => '2023-06-01' }
        )
        .to_return(
          status: 200,
          body: {
            content: [{ type: 'text', text: '4' }],
            model: 'claude-sonnet-4-20250514',
            usage: { input_tokens: 10, output_tokens: 1 }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      action = described_class.new(step: step, context: context, configuration: configuration)
      result = action.call

      expect(result.response).to eq('4')
      expect(result.model).to eq('claude-sonnet-4-20250514')
    end

    it 'interpolates template variables in the prompt' do
      fetch_result = Struct.new(:body, keyword_init: true).new(body: 'price data')
      context.set(:fetch, fetch_result)

      step = AiSentinel::Step.new(name: :analyze, action: :ai_prompt, prompt: 'Analyze: {{fetch.body}}')

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .with(body: hash_including('messages' => [{ 'role' => 'user', 'content' => 'Analyze: price data' }]))
        .to_return(
          status: 200,
          body: { content: [{ type: 'text', text: 'Analysis complete' }], model: 'claude-sonnet-4-20250514',
                  usage: {} }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      action = described_class.new(step: step, context: context, configuration: configuration)
      result = action.call

      expect(result.response).to eq('Analysis complete')
    end

    it 'saves conversation context when remember is true' do
      step = AiSentinel::Step.new(name: :analyze, action: :ai_prompt, prompt: 'Hello', remember: true)

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(
          status: 200,
          body: { content: [{ type: 'text', text: 'Hi there' }], model: 'claude-sonnet-4-20250514', usage: {} }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      action = described_class.new(step: step, context: context, configuration: configuration)
      action.call

      messages = AiSentinel::Persistence::Database.db[:conversation_messages]
                                                  .where(context_key: 'test_workflow:analyze')
                                                  .all

      expect(messages.size).to eq(1)
      expect(messages.first[:user_message]).to eq('Hello')
      expect(messages.first[:assistant_message]).to eq('Hi there')
    end

    it 'includes previous context in subsequent calls' do
      AiSentinel::Persistence::Database.db[:conversation_messages].insert(
        context_key: 'test_workflow:analyze',
        user_message: 'Previous question',
        assistant_message: 'Previous answer',
        created_at: Time.now,
        updated_at: Time.now
      )

      step = AiSentinel::Step.new(name: :analyze, action: :ai_prompt, prompt: 'Follow up')

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .with(body: hash_including(
          'messages' => [
            { 'role' => 'user', 'content' => 'Previous question' },
            { 'role' => 'assistant', 'content' => 'Previous answer' },
            { 'role' => 'user', 'content' => 'Follow up' }
          ]
        ))
        .to_return(
          status: 200,
          body: { content: [{ type: 'text', text: 'Follow up answer' }], model: 'claude-sonnet-4-20250514',
                  usage: {} }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      action = described_class.new(step: step, context: context, configuration: configuration)
      result = action.call

      expect(result.response).to eq('Follow up answer')
    end

    it 'skips context when remember is false' do
      step = AiSentinel::Step.new(name: :analyze, action: :ai_prompt, prompt: 'No memory', remember: false)

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .with(body: hash_including('messages' => [{ 'role' => 'user', 'content' => 'No memory' }]))
        .to_return(
          status: 200,
          body: { content: [{ type: 'text', text: 'Response' }], model: 'claude-sonnet-4-20250514', usage: {} }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      action = described_class.new(step: step, context: context, configuration: configuration)
      action.call

      messages = AiSentinel::Persistence::Database.db[:conversation_messages].all
      expect(messages).to be_empty
    end
  end
end
