# frozen_string_literal: true

module AiSentinel
  module Actions
    class AiPrompt < Base
      Result = Struct.new(:response, :model, :usage, keyword_init: true)

      PROVIDER_MAP = {
        anthropic: Providers::Anthropic,
        openai: Providers::Openai
      }.freeze

      TOOL_MAP = {
        'shell_command' => Tools::ShellCommand
      }.freeze

      def call
        prompt = interpolate(step.params[:prompt])
        system_prompt = step.params[:system] ? interpolate(step.params[:system]) : nil
        model = step.params[:model] || configuration.model
        remember = step.params.fetch(:remember, false)
        tool_executor = build_tool_executor

        provider = build_provider
        provider.chat(
          prompt: prompt,
          system: system_prompt,
          model: model,
          workflow_name: context.workflow_name,
          step_name: step.name,
          remember: remember,
          prompt_template: step.params[:prompt],
          system_template: step.params[:system],
          tool_executor: tool_executor,
          max_tool_rounds: step.params.fetch(:max_tool_rounds, configuration.max_tool_rounds),
          compaction_prompt: step.params[:compaction_prompt]
        )
      end

      private

      def build_provider
        provider_class = PROVIDER_MAP[configuration.provider]
        raise Error, "Unknown provider: #{configuration.provider}" unless provider_class

        provider_class.new(configuration: configuration)
      end

      def build_tool_executor
        tool_names = step.params.fetch(:tools, nil)
        return nil unless tool_names&.any?

        tools = tool_names.map do |name|
          tool_class = TOOL_MAP[name]
          raise Error, "Unknown tool: #{name}" unless tool_class

          tool_class.new
        end

        ToolExecutor.new(tools: tools, configuration: configuration)
      end
    end
  end
end
