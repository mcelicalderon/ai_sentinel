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

  def insert_messages(context_key, count)
    ctx = AiSentinel::Persistence::Database.find_or_create_context(context_key)
    count.times do |i|
      AiSentinel::Persistence::Database.db[:conversation_messages].insert(
        conversation_context_id: ctx[:id],
        user_message: "Question #{i}",
        assistant_message: "Answer #{i}",
        created_at: Time.now + i,
        updated_at: Time.now + i
      )
    end
  end

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

      ctx = AiSentinel::Persistence::Database.db[:conversation_contexts]
                                             .where(context_key: 'test:analyze').first
      messages = AiSentinel::Persistence::Database.db[:conversation_messages]
                                                  .where(conversation_context_id: ctx[:id])
                                                  .all

      expect(messages.size).to eq(1)
      expect(messages.first[:user_message]).to eq('Hello')
      expect(messages.first[:assistant_message]).to eq('Hello!')
    end

    it 'includes previous context in subsequent calls' do
      ctx = AiSentinel::Persistence::Database.find_or_create_context('test:analyze')
      AiSentinel::Persistence::Database.db[:conversation_messages].insert(
        conversation_context_id: ctx[:id],
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
      insert_messages('test:analyze', 4)

      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      provider = described_class.new(configuration: configuration)
      provider.chat(prompt: 'New question', workflow_name: 'test', step_name: 'analyze')

      ctx = AiSentinel::Persistence::Database.db[:conversation_contexts].where(context_key: 'test:analyze').first
      count = AiSentinel::Persistence::Database.db[:conversation_messages]
                                               .where(conversation_context_id: ctx[:id])
                                               .count

      expect(count).to be <= configuration.max_context_messages
    end

    it 'retries with reduced context on token overflow' do
      insert_messages('test:analyze', 4)

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

    context 'with tool use' do
      let(:tool_executor) do
        tool = AiSentinel::Tools::ShellCommand.new
        AiSentinel::ToolExecutor.new(tools: [tool], configuration: configuration)
      end
      let(:json_headers) { { 'Content-Type' => 'application/json' } }

      def tool_call_response(id: 'call_123', command: 'echo hello')
        {
          choices: [{
            message: {
              role: 'assistant', content: nil,
              tool_calls: [{
                id: id, type: 'function',
                function: { name: 'shell_command', arguments: JSON.generate({ command: command }) }
              }]
            }
          }],
          model: 'gpt-4o', usage: {}
        }.to_json
      end

      def text_response(text)
        {
          choices: [{ message: { role: 'assistant', content: text } }],
          model: 'gpt-4o', usage: {}
        }.to_json
      end

      it 'sends tools in request body' do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .with(body: hash_including('tools'))
          .to_return(status: 200, body: text_response('Done'), headers: json_headers)

        provider = described_class.new(configuration: configuration)
        result = provider.chat(
          prompt: 'List files', workflow_name: 'test', step_name: 'review',
          remember: false, tool_executor: tool_executor
        )

        expect(result.response).to eq('Done')
      end

      it 'executes tool calls and loops until final text response' do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(
            { status: 200, body: tool_call_response, headers: json_headers },
            { status: 200, body: text_response('The output was: hello'), headers: json_headers }
          )

        allow(tool_executor).to receive(:execute)
          .and_return('{"stdout":"hello\\n","stderr":"","exit_code":0}')

        provider = described_class.new(configuration: configuration)
        result = provider.chat(
          prompt: 'Run echo hello', workflow_name: 'test', step_name: 'review',
          remember: false, tool_executor: tool_executor
        )

        expect(result.response).to eq('The output was: hello')
        expect(tool_executor).to have_received(:execute).once
      end

      it 'handles tool execution errors gracefully' do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(
            { status: 200, body: tool_call_response(command: 'rm -rf /'), headers: json_headers },
            { status: 200, body: text_response('That command is not allowed.'), headers: json_headers }
          )

        allow(tool_executor).to receive(:execute)
          .and_raise(AiSentinel::Error, 'Command not allowed')

        provider = described_class.new(configuration: configuration)
        result = provider.chat(
          prompt: 'Delete everything', workflow_name: 'test', step_name: 'review',
          remember: false, tool_executor: tool_executor
        )

        expect(result.response).to eq('That command is not allowed.')
      end

      it 'respects max_tool_rounds limit' do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(status: 200, body: tool_call_response(id: 'call_loop', command: 'echo loop'),
                     headers: json_headers)

        allow(tool_executor).to receive(:execute)
          .and_return('{"stdout":"loop\\n","stderr":"","exit_code":0}')

        provider = described_class.new(configuration: configuration)
        provider.chat(
          prompt: 'Keep looping', workflow_name: 'test', step_name: 'review',
          remember: false, tool_executor: tool_executor, max_tool_rounds: 2
        )

        expect(tool_executor).to have_received(:execute).exactly(2).times
      end

      it 'only persists the initial prompt and final response with remember' do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(
            { status: 200, body: tool_call_response(id: 'call_mem', command: 'echo hi'),
              headers: json_headers },
            { status: 200, body: text_response('Final answer'), headers: json_headers }
          )

        allow(tool_executor).to receive(:execute)
          .and_return('{"stdout":"hi\\n","stderr":"","exit_code":0}')

        provider = described_class.new(configuration: configuration)
        provider.chat(
          prompt: 'Run echo hi', workflow_name: 'test', step_name: 'memory_test',
          remember: true, tool_executor: tool_executor
        )

        ctx = AiSentinel::Persistence::Database.db[:conversation_contexts]
                                               .where(context_key: 'test:memory_test').first
        messages = AiSentinel::Persistence::Database.db[:conversation_messages]
                                                    .where(conversation_context_id: ctx[:id]).all

        expect(messages.size).to eq(1)
        expect(messages.first[:user_message]).to eq('Run echo hi')
        expect(messages.first[:assistant_message]).to eq('Final answer')
      end
    end
  end
end
