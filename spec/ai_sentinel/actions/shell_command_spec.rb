# frozen_string_literal: true

RSpec.describe AiSentinel::Actions::ShellCommand do
  let(:configuration) { AiSentinel::Configuration.new }
  let(:context) { AiSentinel::Context.new(workflow_name: 'test', execution_id: 1) }

  describe '#call' do
    it 'executes a shell command and returns stdout' do
      step = AiSentinel::Step.new(name: :check, action: :shell_command, command: "echo 'hello world'")

      action = described_class.new(step: step, context: context, configuration: configuration)
      result = action.call

      expect(result.stdout.strip).to eq('hello world')
      expect(result.exit_code).to eq(0)
      expect(result.success).to be true
    end

    it 'captures stderr and exit code on failure' do
      step = AiSentinel::Step.new(name: :check, action: :shell_command, command: 'ls /nonexistent_path_12345')

      action = described_class.new(step: step, context: context, configuration: configuration)
      result = action.call

      expect(result.exit_code).not_to eq(0)
      expect(result.success).to be false
      expect(result.stderr).not_to be_empty
    end

    it 'interpolates template variables in command' do
      prev_result = Struct.new(:body, keyword_init: true).new(body: 'test_value')
      context.set(:fetch, prev_result)

      step = AiSentinel::Step.new(name: :check, action: :shell_command, command: 'echo {{fetch.body}}')

      action = described_class.new(step: step, context: context, configuration: configuration)
      result = action.call

      expect(result.stdout.strip).to eq('test_value')
    end

    it 'preserves spaces in interpolated values without backslashes' do
      prev_result = Struct.new(:body, keyword_init: true).new(body: 'hello world')
      context.set(:fetch, prev_result)

      step = AiSentinel::Step.new(name: :check, action: :shell_command, command: 'echo {{fetch.body}}')

      action = described_class.new(step: step, context: context, configuration: configuration)
      result = action.call

      expect(result.stdout.strip).to eq('hello world')
      expect(result.stdout).not_to include('\\')
    end

    it 'escapes shell metacharacters in interpolated values' do
      prev_result = Struct.new(:body, keyword_init: true).new(body: '$(whoami) && rm -rf /')
      context.set(:fetch, prev_result)

      step = AiSentinel::Step.new(name: :check, action: :shell_command, command: 'echo {{fetch.body}}')

      action = described_class.new(step: step, context: context, configuration: configuration)
      result = action.call

      expect(result.stdout).to include('$(whoami)')
      expect(result.stdout).not_to include(ENV.fetch('USER', ''))
      expect(result.success).to be true
    end

    it 'escapes backticks in interpolated values' do
      prev_result = Struct.new(:body, keyword_init: true).new(body: '`whoami`')
      context.set(:fetch, prev_result)

      step = AiSentinel::Step.new(name: :check, action: :shell_command, command: 'echo {{fetch.body}}')

      action = described_class.new(step: step, context: context, configuration: configuration)
      result = action.call

      expect(result.stdout.strip).to include('whoami')
      expect(result.stdout).not_to include(ENV.fetch('USER', ''))
    end

    it 'handles values with parentheses' do
      prev_result = Struct.new(:body, keyword_init: true).new(body: 'supports (9 languages)')
      context.set(:fetch, prev_result)

      step = AiSentinel::Step.new(name: :check, action: :shell_command, command: 'echo {{fetch.body}}')

      action = described_class.new(step: step, context: context, configuration: configuration)
      result = action.call

      expect(result.stdout.strip).to eq('supports (9 languages)')
    end

    it 'handles values with single quotes' do
      prev_result = Struct.new(:body, keyword_init: true).new(body: "it's a test")
      context.set(:fetch, prev_result)

      step = AiSentinel::Step.new(name: :check, action: :shell_command, command: 'echo {{fetch.body}}')

      action = described_class.new(step: step, context: context, configuration: configuration)
      result = action.call

      expect(result.stdout.strip).to eq("it's a test")
    end
  end
end
