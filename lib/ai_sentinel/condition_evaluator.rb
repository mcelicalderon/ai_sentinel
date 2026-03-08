# frozen_string_literal: true

module AiSentinel
  module ConditionEvaluator
    OPERATORS = {
      '==' => ->(a, b) { a == b },
      '!=' => ->(a, b) { a != b },
      '>' => ->(a, b) { a.to_f > b.to_f },
      '>=' => ->(a, b) { a.to_f >= b.to_f },
      '<' => ->(a, b) { a.to_f < b.to_f },
      '<=' => ->(a, b) { a.to_f <= b.to_f },
      'contains' => ->(a, b) { a.to_s.include?(b.to_s) },
      'not_contains' => ->(a, b) { !a.to_s.include?(b.to_s) }
    }.freeze

    OPERATOR_PATTERN = /\A(.+?)\s+(==|!=|>=|<=|>|<|contains|not_contains)\s+(.+)\z/

    class << self
      def evaluate(expression, context)
        resolved = resolve_references(expression.strip, context)
        match = OPERATOR_PATTERN.match(resolved)
        return truthy?(resolved) unless match

        left = unquote(match[1].strip)
        operator = match[2]
        right = unquote(match[3].strip)

        OPERATORS[operator].call(left, right)
      end

      private

      def resolve_references(expression, context)
        expression.gsub(/\{\{(\w+)\.(\w+)\}\}/) do
          step_name = ::Regexp.last_match(1).to_sym
          field = ::Regexp.last_match(2).to_sym
          result = context[step_name]
          next '' unless result

          result.respond_to?(field) ? result.public_send(field).to_s : ''
        end
      end

      def unquote(value)
        if (value.start_with?('"') && value.end_with?('"')) ||
           (value.start_with?("'") && value.end_with?("'"))
          value[1..-2]
        else
          value
        end
      end

      def truthy?(value)
        !['', '0', 'false', 'nil', 'null'].include?(value.downcase)
      end
    end
  end
end
