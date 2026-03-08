# frozen_string_literal: true

module AiSentinel
  class CLI < Thor
    module PromptChangeHandler
      private

      def handle_prompt_changes(daemonize: false)
        changes = PromptChangeDetector.detect_changes(AiSentinel.registry)
        return if changes.empty?

        policy = AiSentinel.configuration.on_prompt_change

        changes.each do |change|
          resolve_prompt_change(change, policy: policy, interactive: !daemonize)
        end
      end

      def resolve_prompt_change(change, policy:, interactive:)
        if interactive && policy == :ask
          ask_user_about_prompt_change(change)
        elsif policy == :drop
          drop_context(change)
        else
          keep_context(change)
        end
      end

      def ask_user_about_prompt_change(change)
        say ''
        say "Prompt changed for '#{change.context_key}'."
        say '  1. Keep existing context'
        say '  2. Clear context and start fresh'
        say '  3. Abort'

        answer = ask('  Choice [1/2/3]:')

        case answer.strip
        when '2'
          drop_context(change)
        when '3'
          say 'Aborted.'
          raise SystemExit
        else
          keep_context(change)
        end
      end

      def drop_context(change)
        PromptChangeDetector.clear_context_for(change.context_key)
        update_stored_hash(change)
        say "Cleared context for '#{change.context_key}'."
      end

      def keep_context(change)
        update_stored_hash(change)
        AiSentinel.logger.info("Prompt changed for '#{change.context_key}', keeping existing context.")
      end

      def update_stored_hash(change)
        workflow = AiSentinel.registry[change.workflow_name]
        step = workflow.steps.find { |s| s.name.to_s == change.step_name }
        PromptChangeDetector.update_hash_for(change.context_key, step.params[:prompt], step.params[:system])
      end
    end
  end
end
