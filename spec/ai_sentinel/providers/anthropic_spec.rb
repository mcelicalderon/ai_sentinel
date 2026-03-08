# frozen_string_literal: true

RSpec.describe AiSentinel::Providers::Anthropic, :db do
  let(:configuration) do
    config = AiSentinel::Configuration.new
    config.api_key = 'test-api-key'
    config.max_context_messages = 3
    config.logger = Logger.new(File::NULL)
    config
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
      insert_messages('test:analyze', 4)

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(
          status: 200,
          body: { content: [{ type: 'text', text: 'New answer' }], model: 'claude-sonnet-4-20250514',
                  usage: {} }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      provider = described_class.new(configuration: configuration)
      provider.chat(prompt: 'New question', workflow_name: 'test', step_name: 'analyze')

      ctx = AiSentinel::Persistence::Database.db[:conversation_contexts].where(context_key: 'test:analyze').first
      count = AiSentinel::Persistence::Database.db[:conversation_messages]
                                               .where(conversation_context_id: ctx[:id])
                                               .count

      expect(count).to be <= configuration.max_context_messages
    end

    it 'retries with reduced context on token overflow (400)' do
      insert_messages('test:analyze', 4)

      overflow_body = {
        error: { type: 'invalid_request_error', message: 'prompt is too long: too many tokens' }
      }.to_json
      success_body = {
        content: [{ type: 'text', text: 'OK' }], model: 'claude-sonnet-4-20250514', usage: {}
      }.to_json

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(
          { status: 400, body: overflow_body, headers: { 'Content-Type' => 'application/json' } },
          { status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' } }
        )

      provider = described_class.new(configuration: configuration)
      result = provider.chat(prompt: 'New question', workflow_name: 'test', step_name: 'analyze')

      expect(result.response).to eq('OK')
    end

    it 'retries with reduced context on request too large (413)' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(
          { status: 413, body: { error: { type: 'request_too_large', message: 'Request too large' } }.to_json,
            headers: { 'Content-Type' => 'application/json' } },
          { status: 200,
            body: { content: [{ type: 'text', text: 'OK' }], model: 'claude-sonnet-4-20250514', usage: {} }.to_json,
            headers: { 'Content-Type' => 'application/json' } }
        )

      provider = described_class.new(configuration: configuration)
      result = provider.chat(prompt: 'Hi', workflow_name: 'test', step_name: 'greet', remember: false)

      expect(result.response).to eq('OK')
    end

    it 'raises after exhausting context retries' do
      overflow_body = {
        error: { type: 'invalid_request_error', message: 'too many tokens' }
      }.to_json

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
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

      it 'sends tools in request body' do
        stub_request(:post, 'https://api.anthropic.com/v1/messages')
          .with(body: hash_including('tools'))
          .to_return(
            status: 200,
            body: {
              content: [{ type: 'text', text: 'Done' }],
              model: 'claude-sonnet-4-20250514', usage: {}, stop_reason: 'end_turn'
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        provider = described_class.new(configuration: configuration)
        result = provider.chat(
          prompt: 'List files', workflow_name: 'test', step_name: 'review',
          remember: false, tool_executor: tool_executor
        )

        expect(result.response).to eq('Done')
      end

      it 'executes tool calls and loops until final text response' do
        tool_use_body = {
          content: [
            { type: 'text', text: 'Let me check.' },
            { type: 'tool_use', id: 'toolu_123', name: 'shell_command',
              input: { command: 'echo hello' } }
          ],
          model: 'claude-sonnet-4-20250514', usage: {}, stop_reason: 'tool_use'
        }.to_json

        final_body = {
          content: [{ type: 'text', text: 'The output was: hello' }],
          model: 'claude-sonnet-4-20250514', usage: {}, stop_reason: 'end_turn'
        }.to_json

        stub_request(:post, 'https://api.anthropic.com/v1/messages')
          .to_return(
            { status: 200, body: tool_use_body, headers: { 'Content-Type' => 'application/json' } },
            { status: 200, body: final_body, headers: { 'Content-Type' => 'application/json' } }
          )

        allow(tool_executor).to receive(:execute)
          .with('shell_command', { 'command' => 'echo hello' })
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
        tool_use_body = {
          content: [
            { type: 'tool_use', id: 'toolu_456', name: 'shell_command',
              input: { command: 'rm -rf /' } }
          ],
          model: 'claude-sonnet-4-20250514', usage: {}, stop_reason: 'tool_use'
        }.to_json

        final_body = {
          content: [{ type: 'text', text: 'That command is not allowed.' }],
          model: 'claude-sonnet-4-20250514', usage: {}, stop_reason: 'end_turn'
        }.to_json

        stub_request(:post, 'https://api.anthropic.com/v1/messages')
          .to_return(
            { status: 200, body: tool_use_body, headers: { 'Content-Type' => 'application/json' } },
            { status: 200, body: final_body, headers: { 'Content-Type' => 'application/json' } }
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
        tool_use_body = {
          content: [
            { type: 'tool_use', id: 'toolu_loop', name: 'shell_command',
              input: { command: 'echo loop' } }
          ],
          model: 'claude-sonnet-4-20250514', usage: {}, stop_reason: 'tool_use'
        }.to_json

        stub_request(:post, 'https://api.anthropic.com/v1/messages')
          .to_return(status: 200, body: tool_use_body, headers: { 'Content-Type' => 'application/json' })

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
        tool_use_body = {
          content: [
            { type: 'tool_use', id: 'toolu_mem', name: 'shell_command',
              input: { command: 'echo hi' } }
          ],
          model: 'claude-sonnet-4-20250514', usage: {}, stop_reason: 'tool_use'
        }.to_json

        final_body = {
          content: [{ type: 'text', text: 'Final answer' }],
          model: 'claude-sonnet-4-20250514', usage: {}, stop_reason: 'end_turn'
        }.to_json

        stub_request(:post, 'https://api.anthropic.com/v1/messages')
          .to_return(
            { status: 200, body: tool_use_body, headers: { 'Content-Type' => 'application/json' } },
            { status: 200, body: final_body, headers: { 'Content-Type' => 'application/json' } }
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
