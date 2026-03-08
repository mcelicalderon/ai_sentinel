# frozen_string_literal: true

module AiSentinel
  module Actions
    class Base
      attr_reader :step, :context, :configuration

      def initialize(step:, context:, configuration:)
        @step = step
        @context = context
        @configuration = configuration
      end

      def call
        raise NotImplementedError, "#{self.class}#call must be implemented"
      end

      private

      def interpolate(value)
        context.interpolate(value)
      end
    end
  end
end
