# frozen_string_literal: true

module AiSentinel
  class DSL
    def initialize(name, &block)
      @name = name
      @schedule_expression = nil
      @steps = []
      instance_eval(&block) if block
    end

    def schedule(cron_expression)
      @schedule_expression = cron_expression
    end

    def step(name, action:, condition: nil, **params)
      @steps << Step.new(name: name, action: action, condition: condition, **params)
    end

    def build
      raise Error, "Schedule is required for workflow '#{@name}'" if @schedule_expression.nil?
      raise Error, "At least one step is required for workflow '#{@name}'" if @steps.empty?

      Workflow.new(name: @name, schedule_expression: @schedule_expression, steps: @steps)
    end
  end
end
