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

      !condition.call(context)
    end
  end
end
