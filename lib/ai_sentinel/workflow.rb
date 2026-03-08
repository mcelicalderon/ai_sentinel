# frozen_string_literal: true

module AiSentinel
  class Workflow
    attr_reader :name, :schedule_expression, :steps

    def initialize(name:, schedule_expression:, steps: [])
      @name = name
      @schedule_expression = schedule_expression
      @steps = steps
    end

    def add_step(step)
      @steps << step
    end
  end
end
