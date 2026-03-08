# frozen_string_literal: true

module AiSentinel
  class ContextCompactor
    SUMMARIZATION_PROMPT = <<~PROMPT
      You are a context summarization assistant. Your task is to produce a concise summary that preserves all key information, decisions, data points, and conclusions from the conversation history below.

      The summary should allow a future AI assistant to continue the conversation with full awareness of what has been discussed, analyzed, and decided. Preserve specific numbers, names, dates, and actionable insights.

      Respond with ONLY the summary, no preamble or explanation.
    PROMPT

    attr_reader :context_key, :configuration

    def initialize(context_key:, configuration:)
      @context_key = context_key
      @configuration = configuration
    end

    def compact_if_needed
      return unless Persistence::Database.connected?

      @ctx = Persistence::Database.db[:conversation_contexts].where(context_key: context_key).first
      return unless @ctx
      return unless compaction_needed?

      perform_compaction
    end

    private

    def compaction_needed?
      message_count >= configuration.compaction_threshold
    end

    def message_count
      Persistence::Database.db[:conversation_messages]
                           .where(conversation_context_id: @ctx[:id])
                           .count
    end

    def perform_compaction
      messages_to_summarize = fetch_oldest_messages
      return if messages_to_summarize.empty?

      new_summary = generate_summary(messages_to_summarize, @ctx[:summary])

      Persistence::Database.db.transaction do
        delete_summarized_messages(messages_to_summarize)
        update_context_summary(new_summary, messages_to_summarize.size)
      end

      AiSentinel.logger.info(
        "Compacted #{messages_to_summarize.size} messages for '#{context_key}'"
      )
    end

    def fetch_oldest_messages
      total = message_count
      to_summarize = total - configuration.compaction_buffer

      return [] if to_summarize <= 0

      Persistence::Database.db[:conversation_messages]
                           .where(conversation_context_id: @ctx[:id])
                           .order(:created_at)
                           .limit(to_summarize)
                           .all
    end

    def generate_summary(messages, existing_summary)
      prompt = build_summarization_prompt(messages, existing_summary)
      provider = build_provider

      result = provider.chat(
        prompt: prompt,
        system: SUMMARIZATION_PROMPT,
        workflow_name: nil,
        step_name: nil,
        remember: false
      )

      result.response
    end

    def build_summarization_prompt(messages, existing_summary)
      parts = []

      parts << "## Previous Summary\n#{existing_summary}\n" if existing_summary

      parts << '## Conversation Exchanges to Incorporate'

      messages.each_with_index do |msg, i|
        parts << "Exchange #{i + 1}:"
        parts << "User: #{msg[:user_message]}"
        parts << "Assistant: #{msg[:assistant_message]}"
        parts << ''
      end

      parts << 'Produce an updated summary combining the previous summary (if any) with the new exchanges above.'

      parts.join("\n")
    end

    def delete_summarized_messages(messages)
      ids = messages.map { |m| m[:id] }

      Persistence::Database.db[:conversation_messages]
                           .where(id: ids)
                           .delete
    end

    def update_context_summary(summary_text, newly_summarized_count)
      Persistence::Database.db[:conversation_contexts]
                           .where(id: @ctx[:id])
                           .update(
                             summary: summary_text,
                             messages_summarized_count: @ctx[:messages_summarized_count] + newly_summarized_count,
                             updated_at: Time.now
                           )
    end

    def build_provider
      provider_class = Actions::AiPrompt::PROVIDER_MAP[configuration.provider]
      raise Error, "Unknown provider: #{configuration.provider}" unless provider_class

      provider_class.new(configuration: configuration)
    end
  end
end
