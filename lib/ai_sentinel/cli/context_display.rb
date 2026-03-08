# frozen_string_literal: true

module AiSentinel
  class CLI < Thor
    module ContextDisplay
      private

      def display_context(context_key, limit:)
        ctx = Persistence::Database.db[:conversation_contexts].where(context_key: context_key).first

        unless ctx
          say "No conversation context found for #{context_key}."
          return
        end

        messages = Persistence::Database.db[:conversation_messages]
                                        .where(conversation_context_id: ctx[:id])
                                        .order(Sequel.desc(:created_at))
                                        .limit(limit)
                                        .all
                                        .reverse

        if messages.empty?
          say "No conversation messages found for #{context_key}."
          return
        end

        say "Conversation context for #{context_key} (#{messages.size} messages):"
        say ''
        messages.each do |msg|
          say "  [#{msg[:created_at].strftime('%Y-%m-%d %H:%M:%S')}]"
          say "  User:      #{truncate(msg[:user_message], 200)}"
          say "  Assistant: #{truncate(msg[:assistant_message], 200)}"
          say ''
        end
      end

      def reset_context(context_key)
        ctx = Persistence::Database.db[:conversation_contexts].where(context_key: context_key).first

        unless ctx
          say "No context found for '#{context_key}'."
          return
        end

        msg_count = Persistence::Database.db[:conversation_messages]
                                         .where(conversation_context_id: ctx[:id])
                                         .delete
        Persistence::Database.db[:conversation_contexts]
                             .where(id: ctx[:id])
                             .update(summary: nil, messages_summarized_count: 0, updated_at: Time.now)

        say "Cleared #{msg_count} message(s) and summary from context '#{context_key}'."
      end

      def display_summary(context_key)
        ctx = Persistence::Database.db[:conversation_contexts]
                                   .where(context_key: context_key)
                                   .first

        unless ctx&.fetch(:summary, nil)
          say "No summary found for #{context_key}."
          return
        end

        msg_count = Persistence::Database.db[:conversation_messages]
                                         .where(conversation_context_id: ctx[:id])
                                         .count

        say "Summary for #{context_key}:"
        say "  Messages summarized: #{ctx[:messages_summarized_count]}"
        say "  Recent messages:     #{msg_count}"
        say "  Last updated:        #{ctx[:updated_at].strftime('%Y-%m-%d %H:%M:%S')}"
        say ''
        say ctx[:summary]
      end
    end
  end
end
