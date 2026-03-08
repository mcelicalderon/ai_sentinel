# frozen_string_literal: true

module AiSentinel
  module Providers
    class ContextOverflowError < Error; end

    class Base
      MAX_CONTEXT_RETRIES = 3

      attr_reader :configuration

      def initialize(configuration:)
        @configuration = configuration
      end

      def chat(prompt:, system: nil, model: nil, workflow_name: nil, step_name: nil, remember: true)
        raise NotImplementedError, "#{self.class}#chat must be implemented"
      end

      private

      def with_context_retry(context_limit)
        retries = 0

        begin
          yield context_limit
        rescue ContextOverflowError => e
          retries += 1
          context_limit = (context_limit / 2.0).ceil

          if retries > MAX_CONTEXT_RETRIES || context_limit.zero?
            raise Error, "Context still too large after #{retries} retries: #{e.message}"
          end

          AiSentinel.logger.warn(
            "Context overflow, retrying with #{context_limit} messages (attempt #{retries}/#{MAX_CONTEXT_RETRIES})"
          )
          retry
        end
      end

      def load_context(context_key, limit: nil)
        return [] unless Persistence::Database.connected?

        limit ||= configuration.max_context_messages
        messages = []

        summary = load_summary(context_key)
        if summary
          messages << { 'role' => 'user', 'content' => "Context from previous conversations:\n#{summary}" }
          messages << { 'role' => 'assistant',
                        'content' => 'Understood, I have the context from previous conversations.' }
        end

        Persistence::Database.db[:conversation_messages]
                             .where(context_key: context_key)
                             .order(:created_at)
                             .last(limit)
                             .each do |row|
          messages << { 'role' => 'user', 'content' => row[:user_message] }
          messages << { 'role' => 'assistant', 'content' => row[:assistant_message] }
        end

        messages
      end

      def load_summary(context_key)
        row = Persistence::Database.db[:context_summaries]
                                   .where(context_key: context_key)
                                   .first
        row&.fetch(:summary)
      end

      def save_context(context_key, user_message, assistant_message)
        return unless Persistence::Database.connected?

        Persistence::Database.db[:conversation_messages].insert(
          context_key: context_key,
          user_message: user_message,
          assistant_message: assistant_message,
          created_at: Time.now,
          updated_at: Time.now
        )

        prune_old_messages(context_key)
        compact_context(context_key)
      end

      def compact_context(context_key)
        ContextCompactor.new(context_key: context_key, configuration: configuration).compact_if_needed
      rescue StandardError => e
        AiSentinel.logger.warn("Context compaction failed for '#{context_key}': #{e.message}")
      end

      def prune_old_messages(context_key)
        count = Persistence::Database.db[:conversation_messages]
                                     .where(context_key: context_key)
                                     .count

        return unless count > configuration.max_context_messages

        oldest_to_keep = Persistence::Database.db[:conversation_messages]
                                              .where(context_key: context_key)
                                              .order(Sequel.desc(:created_at))
                                              .limit(configuration.max_context_messages)
                                              .select(:id)

        Persistence::Database.db[:conversation_messages]
                             .where(context_key: context_key)
                             .exclude(id: oldest_to_keep)
                             .delete
      end
    end
  end
end
