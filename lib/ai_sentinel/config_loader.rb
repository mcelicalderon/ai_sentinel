# frozen_string_literal: true

require 'yaml'

module AiSentinel
  class ConfigLoader
    DEFAULT_CONFIG_FILES = %w[ai_sentinel.yml ai_sentinel.yaml].freeze
    VALID_ACTIONS = %w[http_get http_post ai_prompt shell_command].freeze

    attr_reader :config_path, :raw_config

    def initialize(config_path = nil)
      @config_path = resolve_config_path(config_path)
      @raw_config = load_file
    end

    def load!
      validate!
      apply_global_config
      register_workflows
    end

    private

    def resolve_config_path(path)
      return File.expand_path(path) if path

      DEFAULT_CONFIG_FILES.each do |name|
        expanded = File.expand_path(name)
        return expanded if File.exist?(expanded)
      end

      raise ConfigurationError, 'No config file found. Create ai_sentinel.yml or specify a path.'
    end

    def load_file
      raise ConfigurationError, "Config file not found: #{config_path}" unless File.exist?(config_path)

      YAML.safe_load_file(config_path, permitted_classes: [Symbol]) || {}
    rescue Psych::SyntaxError => e
      raise ConfigurationError, "Invalid YAML in #{config_path}: #{e.message}"
    end

    def validate!
      validate_global
      validate_workflows
    end

    def validate_global
      global = raw_config['global'] || {}
      provider = global['provider']
      return unless provider

      valid = Configuration::VALID_PROVIDERS.map(&:to_s)
      return if valid.include?(provider)

      raise ConfigurationError, "Invalid provider '#{provider}'. Valid: #{valid.join(', ')}"
    end

    def validate_workflows
      workflows = raw_config['workflows']
      raise ConfigurationError, "No workflows defined in #{config_path}" if workflows.nil? || workflows.empty?

      workflows.each do |name, definition|
        validate_workflow(name, definition)
      end
    end

    def validate_workflow(name, definition)
      raise ConfigurationError, "Workflow '#{name}' is missing 'schedule'" unless definition['schedule']

      steps = definition['steps']
      raise ConfigurationError, "Workflow '#{name}' has no steps" if steps.nil? || steps.empty?

      steps.each_with_index do |step, index|
        validate_step(name, step, index)
      end
    end

    def validate_step(workflow_name, step, index)
      id = step['id'] || "step #{index + 1}"
      action = step['action']

      raise ConfigurationError, "Step '#{id}' in '#{workflow_name}' is missing 'id'" unless step['id']
      raise ConfigurationError, "Step '#{id}' in '#{workflow_name}' is missing 'action'" unless action
      return if VALID_ACTIONS.include?(action)

      raise ConfigurationError,
            "Step '#{id}' in '#{workflow_name}' has invalid action '#{action}'. Valid: #{VALID_ACTIONS.join(', ')}"
    end

    def apply_global_config
      global = raw_config['global'] || {}

      AiSentinel.configure do |config|
        config.provider = global['provider'].to_sym if global['provider']
        config.model = global['model'] if global['model']
        config.database_path = File.expand_path(global['database']) if global['database']
        config.max_context_messages = global['max_context_messages'] if global['max_context_messages']
        config.base_url = global['base_url'] if global['base_url']
      end
    end

    def register_workflows
      raw_config['workflows'].each do |name, definition|
        steps = definition['steps'].map { |s| build_step(s) }
        workflow = Workflow.new(
          name: name,
          schedule_expression: definition['schedule'],
          steps: steps
        )
        AiSentinel.registry[name] = workflow
      end
    end

    def build_step(step_hash)
      params = (step_hash['params'] || {}).transform_keys(&:to_sym)
      condition = build_condition(step_hash['when']) if step_hash['when']

      Step.new(
        name: step_hash['id'],
        action: step_hash['action'],
        condition: condition,
        **params
      )
    end

    def build_condition(expression)
      lambda do |ctx|
        ConditionEvaluator.evaluate(expression, ctx)
      end
    end
  end
end
