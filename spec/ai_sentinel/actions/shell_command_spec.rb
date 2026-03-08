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

      step = AiSentinel::Step.new(name: :check, action: :shell_command, command: "echo '{{fetch.body}}'")

      action = described_class.new(step: step, context: context, configuration: configuration)
      result = action.call

      expect(result.stdout.strip).to eq('test_value')
    end
  end
end
