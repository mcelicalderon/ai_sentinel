# frozen_string_literal: true

module AiSentinel
  module Providers
    class Base
      attr_reader :configuration

      def initialize(configuration:)
        @configuration = configuration
      end

      def chat(prompt:, system: nil, model: nil, workflow_name: nil, step_name: nil, remember: true)
        raise NotImplementedError, "#{self.class}#chat must be implemented"
      end

      private

      def load_context(context_key)
        return [] unless Persistence::Database.connected?

        Persistence::Database.db[:conversation_messages]
                             .where(context_key: context_key)
                             .order(:created_at)
                             .last(configuration.max_context_messages)
                             .flat_map do |row|
          [
            { 'role' => 'user', 'content' => row[:user_message] },
            { 'role' => 'assistant', 'content' => row[:assistant_message] }
          ]
        end
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
