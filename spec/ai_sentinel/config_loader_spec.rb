# frozen_string_literal: true

require 'tmpdir'

RSpec.describe AiSentinel::ConfigLoader do
  let(:tmpdir) { Dir.mktmpdir }
  let(:config_path) { File.join(tmpdir, 'ai_sentinel.yml') }

  after { FileUtils.remove_entry(tmpdir) }

  def write_config(content)
    File.write(config_path, content)
  end

  describe '#load!' do
    it 'registers workflows from a YAML config file' do
      write_config(<<~YAML)
        global:
          provider: anthropic
          model: claude-sonnet-4-20250514

        workflows:
          test_workflow:
            schedule: "0 9 * * *"
            steps:
              - id: fetch
                action: http_get
                params:
                  url: "https://example.com"
      YAML

      described_class.new(config_path).load!

      expect(AiSentinel.registry).to have_key('test_workflow')
      expect(AiSentinel.registry['test_workflow'].schedule_expression).to eq('0 9 * * *')
      expect(AiSentinel.registry['test_workflow'].steps.size).to eq(1)
    end

    it 'parses step attributes from YAML' do
      write_config(<<~YAML)
        workflows:
          test_workflow:
            schedule: "0 9 * * *"
            steps:
              - id: fetch
                action: http_get
                params:
                  url: "https://example.com"
      YAML

      described_class.new(config_path).load!

      step = AiSentinel.registry['test_workflow'].steps.first
      expect(step.name).to eq(:fetch)
      expect(step.action).to eq(:http_get)
      expect(step.params[:url]).to eq('https://example.com')
    end

    it 'applies global configuration' do
      write_config(<<~YAML)
        global:
          provider: anthropic
          model: custom-model
          max_context_messages: 25

        workflows:
          test:
            schedule: "* * * * *"
            steps:
              - id: ping
                action: shell_command
                params:
                  command: "echo hello"
      YAML

      described_class.new(config_path).load!

      expect(AiSentinel.configuration.model).to eq('custom-model')
      expect(AiSentinel.configuration.max_context_messages).to eq(25)
    end

    it 'applies log_file from global configuration' do
      write_config(<<~YAML)
        global:
          log_file: "./logs/ai_sentinel.log"

        workflows:
          test:
            schedule: "* * * * *"
            steps:
              - id: ping
                action: shell_command
                params:
                  command: "echo hello"
      YAML

      described_class.new(config_path).load!

      expect(AiSentinel.configuration.log_file).to eq(File.expand_path('./logs/ai_sentinel.log'))
    end

    it 'applies log rotation settings from global configuration' do
      write_config(<<~YAML)
        global:
          log_file: "./test.log"
          log_file_size: 5242880
          log_files: 3

        workflows:
          test:
            schedule: "* * * * *"
            steps:
              - id: ping
                action: shell_command
                params:
                  command: "echo hello"
      YAML

      described_class.new(config_path).load!

      expect(AiSentinel.configuration.log_file_size).to eq(5_242_880)
      expect(AiSentinel.configuration.log_files).to eq(3)
    end

    it 'applies base_url from global configuration' do
      write_config(<<~YAML)
        global:
          provider: openai
          base_url: "http://localhost:11434/v1/chat/completions"

        workflows:
          test:
            schedule: "* * * * *"
            steps:
              - id: ping
                action: shell_command
                params:
                  command: "echo hello"
      YAML

      described_class.new(config_path).load!

      expect(AiSentinel.configuration.base_url).to eq('http://localhost:11434/v1/chat/completions')
      expect(AiSentinel.configuration.provider).to eq(:openai)
    end

    it 'loads multiple workflows' do
      write_config(<<~YAML)
        workflows:
          workflow_a:
            schedule: "0 9 * * *"
            steps:
              - id: step_a
                action: http_get
                params:
                  url: "https://a.example.com"
          workflow_b:
            schedule: "0 18 * * *"
            steps:
              - id: step_b
                action: shell_command
                params:
                  command: "echo b"
      YAML

      described_class.new(config_path).load!

      expect(AiSentinel.registry.keys).to contain_exactly('workflow_a', 'workflow_b')
    end

    it 'builds conditions from when expressions' do
      write_config(<<~YAML)
        workflows:
          test:
            schedule: "* * * * *"
            steps:
              - id: fetch
                action: http_get
                params:
                  url: "https://example.com"
              - id: notify
                action: http_post
                when: '{{fetch.status}} == 200'
                params:
                  url: "https://hooks.example.com"
      YAML

      described_class.new(config_path).load!

      notify_step = AiSentinel.registry['test'].steps.last
      expect(notify_step.condition).to be_a(Proc)
    end
  end

  describe 'validation' do
    it 'raises when config file is not found' do
      expect { described_class.new('/nonexistent/path.yml') }
        .to raise_error(AiSentinel::ConfigurationError, /Config file not found/)
    end

    it 'raises on invalid YAML' do
      write_config('invalid: yaml: content: [')

      expect { described_class.new(config_path) }
        .to raise_error(AiSentinel::ConfigurationError, /Invalid YAML/)
    end

    it 'raises when no workflows are defined' do
      write_config(<<~YAML)
        global:
          provider: anthropic
      YAML

      expect { described_class.new(config_path).load! }
        .to raise_error(AiSentinel::ConfigurationError, /No workflows defined/)
    end

    it 'raises when workflow is missing schedule' do
      write_config(<<~YAML)
        workflows:
          test:
            steps:
              - id: fetch
                action: http_get
                params:
                  url: "https://example.com"
      YAML

      expect { described_class.new(config_path).load! }
        .to raise_error(AiSentinel::ConfigurationError, /missing 'schedule'/)
    end

    it 'raises when workflow has no steps' do
      write_config(<<~YAML)
        workflows:
          test:
            schedule: "* * * * *"
            steps: []
      YAML

      expect { described_class.new(config_path).load! }
        .to raise_error(AiSentinel::ConfigurationError, /has no steps/)
    end

    it 'raises when step is missing id' do
      write_config(<<~YAML)
        workflows:
          test:
            schedule: "* * * * *"
            steps:
              - action: http_get
                params:
                  url: "https://example.com"
      YAML

      expect { described_class.new(config_path).load! }
        .to raise_error(AiSentinel::ConfigurationError, /missing 'id'/)
    end

    it 'raises when step is missing action' do
      write_config(<<~YAML)
        workflows:
          test:
            schedule: "* * * * *"
            steps:
              - id: fetch
                params:
                  url: "https://example.com"
      YAML

      expect { described_class.new(config_path).load! }
        .to raise_error(AiSentinel::ConfigurationError, /missing 'action'/)
    end

    it 'raises when step has invalid action' do
      write_config(<<~YAML)
        workflows:
          test:
            schedule: "* * * * *"
            steps:
              - id: fetch
                action: invalid_action
                params:
                  url: "https://example.com"
      YAML

      expect { described_class.new(config_path).load! }
        .to raise_error(AiSentinel::ConfigurationError, /invalid action 'invalid_action'/)
    end

    it 'raises when provider is invalid' do
      write_config(<<~YAML)
        global:
          provider: invalid_provider
        workflows:
          test:
            schedule: "* * * * *"
            steps:
              - id: fetch
                action: http_get
                params:
                  url: "https://example.com"
      YAML

      expect { described_class.new(config_path).load! }
        .to raise_error(AiSentinel::ConfigurationError, /Invalid provider/)
    end
  end

  describe 'default config file detection' do
    it 'finds ai_sentinel.yml in current directory' do
      default_path = File.join(tmpdir, 'ai_sentinel.yml')
      File.write(default_path, <<~YAML)
        workflows:
          test:
            schedule: "* * * * *"
            steps:
              - id: ping
                action: shell_command
                params:
                  command: "echo hello"
      YAML

      Dir.chdir(tmpdir) do
        loader = described_class.new
        loader.load!
      end

      expect(AiSentinel.registry).to have_key('test')
    end
  end
end
