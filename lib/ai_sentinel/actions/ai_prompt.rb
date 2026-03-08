# frozen_string_literal: true

module AiSentinel
  module Actions
    class AiPrompt < Base
      Result = Struct.new(:response, :model, :usage, keyword_init: true)

      def call
        prompt = interpolate(step.params[:prompt])
        system_prompt = step.params[:system] ? interpolate(step.params[:system]) : nil
        model = step.params[:model] || configuration.model
        remember = step.params.fetch(:remember, true)

        provider = Providers::Anthropic.new(configuration: configuration)
        provider.chat(
          prompt: prompt,
          system: system_prompt,
          model: model,
          workflow_name: context.workflow_name,
          step_name: step.name,
          remember: remember
        )
      end
    end
  end
end
