# frozen_string_literal: true

RSpec.describe AiSentinel::Tools::ShellCommand do
  subject(:tool) { described_class.new }

  describe '#name' do
    it 'returns shell_command' do
      expect(tool.name).to eq('shell_command')
    end
  end

  describe '#description' do
    it 'describes the tool purpose' do
      expect(tool.description).to include('shell command')
    end
  end

  describe '#input_schema' do
    it 'defines a command parameter' do
      schema = tool.input_schema
      expect(schema[:type]).to eq('object')
      expect(schema[:properties]).to have_key(:command)
      expect(schema[:required]).to eq(['command'])
    end
  end

  describe '#to_anthropic_schema' do
    it 'returns Anthropic-formatted tool definition' do
      schema = tool.to_anthropic_schema
      expect(schema[:name]).to eq('shell_command')
      expect(schema[:description]).to be_a(String)
      expect(schema[:input_schema]).to be_a(Hash)
    end
  end

  describe '#to_openai_schema' do
    it 'returns OpenAI-formatted tool definition' do
      schema = tool.to_openai_schema
      expect(schema[:type]).to eq('function')
      expect(schema[:function][:name]).to eq('shell_command')
      expect(schema[:function][:parameters]).to be_a(Hash)
    end
  end
end
