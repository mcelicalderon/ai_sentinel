# frozen_string_literal: true

module AiSentinel
  module Actions
    class AiPrompt < Base
      Result = Struct.new(:response, :model, :usage, keyword_init: true)

      PROVIDER_MAP = {
        anthropic: Providers::Anthropic,
        openai: Providers::Openai
      }.freeze

      def call
        prompt = interpolate(step.params[:prompt])
        system_prompt = step.params[:system] ? interpolate(step.params[:system]) : nil
        model = step.params[:model] || configuration.model
        remember = step.params.fetch(:remember, false)

        provider = build_provider
        provider.chat(
          prompt: prompt,
          system: system_prompt,
          model: model,
          workflow_name: context.workflow_name,
          step_name: step.name,
          remember: remember
        )
      end

      private

      def build_provider
        provider_class = PROVIDER_MAP[configuration.provider]
        raise Error, "Unknown provider: #{configuration.provider}" unless provider_class

        provider_class.new(configuration: configuration)
      end
    end
  end
end
