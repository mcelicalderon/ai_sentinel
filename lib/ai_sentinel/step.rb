# frozen_string_literal: true

module AiSentinel
  class Step
    attr_reader :name, :action, :params, :condition

    def initialize(name:, action:, condition: nil, **params)
      @name = name.to_sym
      @action = action.to_sym
      @params = params
      @condition = condition
    end

    def skip?(context)
      return false if condition.nil?

      if condition.respond_to?(:call)
        !condition.call(context)
      else
        !ConditionEvaluator.evaluate(condition.to_s, context)
      end
    end
  end
end
