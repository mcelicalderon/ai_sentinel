# frozen_string_literal: true

require 'faraday'
require 'json'

module AiSentinel
  module Providers
    class Anthropic < Base
      API_URL = 'https://api.anthropic.com/v1/messages'
      API_VERSION = '2023-06-01'

      def chat(prompt:, system: nil, model: nil, workflow_name: nil, step_name: nil, remember: true)
        model ||= configuration.model
        context_key = "#{workflow_name}:#{step_name}"

        messages = build_messages(prompt, context_key, remember)
        body = build_request_body(messages, model, system)
        response_data = send_request(body)

        assistant_text = extract_text(response_data)
        save_context(context_key, prompt, assistant_text) if remember

        Actions::AiPrompt::Result.new(
          response: assistant_text,
          model: response_data['model'],
          usage: response_data['usage']
        )
      end

      private

      def build_messages(prompt, context_key, remember)
        messages = []
        messages.concat(load_context(context_key)) if remember
        messages << { 'role' => 'user', 'content' => prompt }
        messages
      end

      def build_request_body(messages, model, system)
        body = { model: model, max_tokens: 4096, messages: messages }
        body[:system] = system if system
        body
      end

      def send_request(body)
        response = connection.post do |req|
          req.body = JSON.generate(body)
        end

        data = JSON.parse(response.body)
        raise Error, "Anthropic API error: #{data['error']&.fetch('message', response.body)}" unless response.success?

        data
      end

      def extract_text(response_data)
        response_data.dig('content', 0, 'text') || ''
      end

      def connection
        @connection ||= Faraday.new(url: API_URL) do |f|
          f.headers['x-api-key'] = configuration.api_key
          f.headers['anthropic-version'] = API_VERSION
          f.headers['content-type'] = 'application/json'
          f.adapter Faraday.default_adapter
        end
      end

      def load_context(context_key)
        return [] unless Persistence::Database.connected?

        rows = Persistence::Database.db[:conversation_messages]
                                    .where(context_key: context_key)
                                    .order(:created_at)
                                    .last(configuration.max_context_messages)

        rows.flat_map do |row|
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
