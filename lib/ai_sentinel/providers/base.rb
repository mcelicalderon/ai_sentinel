# frozen_string_literal: true

module AiSentinel
  module Providers
    class Base
      attr_reader :configuration

      def initialize(configuration:)
        @configuration = configuration
      end

      def chat(prompt:, system: nil, model: nil, workflow_name: nil, step_name: nil, remember: true)
        raise NotImplementedError, "#{self.class}#chat must be implemented"
      end
    end
  end
end
