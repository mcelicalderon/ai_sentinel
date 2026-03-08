# frozen_string_literal: true

require 'digest'

module AiSentinel
  class PromptChangeDetector
    Change = Struct.new(:context_key, :workflow_name, :step_name, keyword_init: true)

    class << self
      def compute_hash(prompt_template, system_template = nil)
        content = "#{prompt_template}\n---\n#{system_template}"
        Digest::SHA256.hexdigest(content)
      end

      def save_hash(context_key, prompt_hash)
        return unless Persistence::Database.connected?

        ctx = Persistence::Database.find_or_create_context(context_key)

        Persistence::Database.db[:conversation_contexts]
                             .where(id: ctx[:id])
                             .update(prompt_hash: prompt_hash, updated_at: Time.now)
      end

      def detect_changes(registry)
        return [] unless Persistence::Database.connected?

        changes = []

        registry.each do |workflow_name, workflow|
          workflow.steps.each do |step|
            change = check_step(workflow_name, step)
            changes << change if change
          end
        end

        changes
      end

      def clear_context_for(context_key)
        return unless Persistence::Database.connected?

        ctx = Persistence::Database.db[:conversation_contexts].where(context_key: context_key).first
        return unless ctx

        Persistence::Database.db[:conversation_messages]
                             .where(conversation_context_id: ctx[:id])
                             .delete
        Persistence::Database.db[:conversation_contexts]
                             .where(id: ctx[:id])
                             .update(summary: nil, messages_summarized_count: 0, updated_at: Time.now)
      end

      def update_hash_for(context_key, prompt_template, system_template = nil)
        save_hash(context_key, compute_hash(prompt_template, system_template))
      end

      private

      def check_step(workflow_name, step)
        return unless step.action == :ai_prompt && step.params.fetch(:remember, false)

        context_key = "#{workflow_name}:#{step.name}"
        current_hash = compute_hash(step.params[:prompt], step.params[:system])
        ctx = Persistence::Database.db[:conversation_contexts]
                                   .where(context_key: context_key)
                                   .first

        return unless ctx && ctx[:prompt_hash] && ctx[:prompt_hash] != current_hash

        Change.new(context_key: context_key, workflow_name: workflow_name.to_s, step_name: step.name.to_s)
      end
    end
  end
end
