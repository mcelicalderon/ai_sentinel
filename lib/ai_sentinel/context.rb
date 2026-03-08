# frozen_string_literal: true

module AiSentinel
  class Context
    attr_reader :results, :workflow_name, :execution_id

    def initialize(workflow_name:, execution_id:)
      @workflow_name = workflow_name
      @execution_id = execution_id
      @results = {}
    end

    def [](step_name)
      @results[step_name.to_sym]
    end

    def set(step_name, result)
      @results[step_name.to_sym] = result
    end

    def interpolate(template)
      return template unless template.is_a?(String)

      template.gsub(/\{\{(\w+)\.(\w+)\}\}/) do
        step_name = ::Regexp.last_match(1).to_sym
        field = ::Regexp.last_match(2).to_sym
        step_result = @results[step_name]
        next "{{#{::Regexp.last_match(1)}.#{::Regexp.last_match(2)}}}" unless step_result

        step_result.respond_to?(field) ? step_result.public_send(field).to_s : step_result.to_s
      end
    end
  end
end
