# frozen_string_literal: true

module AiSentinel
  module Tools
    REGISTRY = {}.freeze

    class Base
      def name
        raise NotImplementedError, "#{self.class}#name must be implemented"
      end

      def description
        raise NotImplementedError, "#{self.class}#description must be implemented"
      end

      def input_schema
        raise NotImplementedError, "#{self.class}#input_schema must be implemented"
      end

      def execute(input)
        raise NotImplementedError, "#{self.class}#execute must be implemented"
      end

      def to_anthropic_schema
        {
          name: name,
          description: description,
          input_schema: input_schema
        }
      end

      def to_openai_schema
        {
          type: 'function',
          function: {
            name: name,
            description: description,
            parameters: input_schema
          }
        }
      end
    end
  end
end
