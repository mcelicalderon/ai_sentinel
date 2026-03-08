# frozen_string_literal: true

require 'sequel'
require 'sqlite3'
require 'fileutils'

module AiSentinel
  module Persistence
    module Database
      class << self
        attr_reader :db

        def setup(database_path)
          dir = File.dirname(database_path)
          unless File.directory?(dir)
            FileUtils.mkdir_p(dir)
            File.chmod(0o700, dir)
          end

          @db = Sequel.sqlite(database_path)
          run_migrations
        end

        def connected?
          !@db.nil?
        end

        def find_or_create_context(context_key)
          row = @db[:conversation_contexts].where(context_key: context_key).first
          return row if row

          now = Time.now
          id = @db[:conversation_contexts].insert(
            context_key: context_key, messages_summarized_count: 0,
            created_at: now, updated_at: now
          )
          @db[:conversation_contexts].where(id: id).first
        end

        def disconnect
          @db&.disconnect
          @db = nil
        end

        private

        def run_migrations
          create_execution_logs_table
          create_step_results_table
          create_conversation_contexts_table
          create_conversation_messages_table
        end

        def create_execution_logs_table
          @db.create_table?(:execution_logs) do
            primary_key :id
            String :workflow_name, null: false
            String :status, null: false, default: 'running'
            Time :started_at, null: false
            Time :finished_at
            String :error_message
            Time :created_at, null: false
            Time :updated_at, null: false

            index :workflow_name
            index :status
          end
        end

        def create_step_results_table
          @db.create_table?(:step_results) do
            primary_key :id
            foreign_key :execution_log_id, :execution_logs, null: false
            String :step_name, null: false
            String :action, null: false
            String :status, null: false
            Text :result_data
            String :error_message
            Time :started_at, null: false
            Time :finished_at
            Time :created_at, null: false

            index :execution_log_id
          end
        end

        def create_conversation_contexts_table
          @db.create_table?(:conversation_contexts) do
            primary_key :id
            String :context_key, null: false, unique: true
            String :prompt_hash
            Text :summary
            Integer :messages_summarized_count, null: false, default: 0
            Time :created_at, null: false
            Time :updated_at, null: false

            index :context_key
          end
        end

        def create_conversation_messages_table
          @db.create_table?(:conversation_messages) do
            primary_key :id
            foreign_key :conversation_context_id, :conversation_contexts, null: false
            Text :user_message, null: false
            Text :assistant_message, null: false
            Time :created_at, null: false
            Time :updated_at, null: false

            index :conversation_context_id
          end
        end
      end
    end
  end
end
