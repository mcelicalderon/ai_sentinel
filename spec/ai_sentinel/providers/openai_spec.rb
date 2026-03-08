# frozen_string_literal: true

RSpec.describe AiSentinel::Providers::Openai, :db do
  let(:configuration) do
    config = AiSentinel::Configuration.new
    config.provider = :openai
    config.api_key = 'test-openai-key'
    config.max_context_messages = 3
    config.logger = Logger.new(File::NULL)
    config
  end
  let(:success_body) do
    {
      choices: [{ message: { role: 'assistant', content: 'Hello!' } }],
      model: 'gpt-4o',
      usage: { prompt_tokens: 10, completion_tokens: 5 }
    }.to_json
  end

  before { AiSentinel.instance_variable_set(:@configuration, configuration) }

  describe '#chat' do
    it 'sends a request to the OpenAI API' do
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .with(headers: { 'Authorization' => 'Bearer test-openai-key' })
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      provider = described_class.new(configuration: configuration)
      result = provider.chat(prompt: 'Hi', workflow_name: 'test', step_name: 'greet', remember: false)

      expect(result).to be_a(AiSentinel::Actions::AiPrompt::Result)
      expect(result.response).to eq('Hello!')
      expect(result.model).to eq('gpt-4o')
    end

    it 'includes system prompt as first message' do
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .with(body: hash_including(
          'messages' => [
            { 'role' => 'system', 'content' => 'You are helpful' },
            { 'role' => 'user', 'content' => 'Hi' }
          ]
        ))
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      provider = described_class.new(configuration: configuration)
      provider.chat(prompt: 'Hi', system: 'You are helpful', workflow_name: 'test', step_name: 'greet', remember: false)
    end

    it 'uses the configured model' do
      configuration.model = 'gpt-4o-mini'

      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .with(body: hash_including('model' => 'gpt-4o-mini'))
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      provider = described_class.new(configuration: configuration)
      provider.chat(prompt: 'Hi', workflow_name: 'test', step_name: 'greet', remember: false)
    end

    it 'raises on API error' do
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
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

    it 'uses base_url when configured' do
      configuration.base_url = 'http://localhost:11434/v1/chat/completions'

      stub_request(:post, 'http://localhost:11434/v1/chat/completions')
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      provider = described_class.new(configuration: configuration)
      result = provider.chat(prompt: 'Hi', workflow_name: 'test', step_name: 'greet', remember: false)

      expect(result.response).to eq('Hello!')
    end

    it 'saves conversation context when remember is true' do
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      provider = described_class.new(configuration: configuration)
      provider.chat(prompt: 'Hello', workflow_name: 'test', step_name: 'analyze')

      messages = AiSentinel::Persistence::Database.db[:conversation_messages]
                                                  .where(context_key: 'test:analyze')
                                                  .all

      expect(messages.size).to eq(1)
      expect(messages.first[:user_message]).to eq('Hello')
      expect(messages.first[:assistant_message]).to eq('Hello!')
    end

    it 'includes previous context in subsequent calls' do
      AiSentinel::Persistence::Database.db[:conversation_messages].insert(
        context_key: 'test:analyze',
        user_message: 'Previous question',
        assistant_message: 'Previous answer',
        created_at: Time.now,
        updated_at: Time.now
      )

      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .with(body: hash_including(
          'messages' => [
            { 'role' => 'user', 'content' => 'Previous question' },
            { 'role' => 'assistant', 'content' => 'Previous answer' },
            { 'role' => 'user', 'content' => 'Follow up' }
          ]
        ))
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      provider = described_class.new(configuration: configuration)
      result = provider.chat(prompt: 'Follow up', workflow_name: 'test', step_name: 'analyze')

      expect(result.response).to eq('Hello!')
    end

    it 'skips context when remember is false' do
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .with(body: hash_including('messages' => [{ 'role' => 'user', 'content' => 'No memory' }]))
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      provider = described_class.new(configuration: configuration)
      provider.chat(prompt: 'No memory', workflow_name: 'test', step_name: 'analyze', remember: false)

      messages = AiSentinel::Persistence::Database.db[:conversation_messages].all
      expect(messages).to be_empty
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

      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      provider = described_class.new(configuration: configuration)
      provider.chat(prompt: 'New question', workflow_name: 'test', step_name: 'analyze')

      count = AiSentinel::Persistence::Database.db[:conversation_messages]
                                               .where(context_key: 'test:analyze')
                                               .count

      expect(count).to be <= configuration.max_context_messages
    end

    it 'retries with reduced context on token overflow' do
      4.times do |i|
        AiSentinel::Persistence::Database.db[:conversation_messages].insert(
          context_key: 'test:analyze',
          user_message: "Q#{i}",
          assistant_message: "A#{i}",
          created_at: Time.now + i,
          updated_at: Time.now + i
        )
      end

      overflow_body = {
        error: { message: "This model's maximum context length is 8192 tokens" }
      }.to_json

      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(
          { status: 400, body: overflow_body, headers: { 'Content-Type' => 'application/json' } },
          { status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' } }
        )

      provider = described_class.new(configuration: configuration)
      result = provider.chat(prompt: 'New question', workflow_name: 'test', step_name: 'analyze')

      expect(result.response).to eq('Hello!')
    end

    it 'retries on context_length_exceeded error code' do
      overflow_body = {
        error: { message: 'context_length_exceeded', code: 'context_length_exceeded' }
      }.to_json

      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(
          { status: 400, body: overflow_body, headers: { 'Content-Type' => 'application/json' } },
          { status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' } }
        )

      provider = described_class.new(configuration: configuration)
      result = provider.chat(prompt: 'Hi', workflow_name: 'test', step_name: 'greet', remember: false)

      expect(result.response).to eq('Hello!')
    end

    it 'raises after exhausting context retries' do
      overflow_body = {
        error: { message: "This model's maximum context length is 8192 tokens" }
      }.to_json

      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(status: 400, body: overflow_body, headers: { 'Content-Type' => 'application/json' })

      provider = described_class.new(configuration: configuration)

      expect do
        provider.chat(prompt: 'Hi', workflow_name: 'test', step_name: 'greet', remember: false)
      end.to raise_error(AiSentinel::Error, /Context still too large after/)
    end
  end
end
