# frozen_string_literal: true

require 'faraday'
require 'json'

module AiSentinel
  module Providers
    class Openai < Base
      def chat(prompt:, system: nil, model: nil, workflow_name: nil, step_name: nil, remember: true)
        model ||= configuration.model
        context_key = "#{workflow_name}:#{step_name}"

        messages = build_messages(prompt, system, context_key, remember)
        response_data = send_request(messages, model)

        assistant_text = extract_text(response_data)
        save_context(context_key, prompt, assistant_text) if remember

        Actions::AiPrompt::Result.new(
          response: assistant_text,
          model: response_data['model'],
          usage: response_data['usage']
        )
      end

      private

      def build_messages(prompt, system, context_key, remember)
        messages = []
        messages << { 'role' => 'system', 'content' => system } if system
        messages.concat(load_context(context_key)) if remember
        messages << { 'role' => 'user', 'content' => prompt }
        messages
      end

      def send_request(messages, model)
        body = { model: model, messages: messages }
        response = connection.post do |req|
          req.body = JSON.generate(body)
        end

        data = JSON.parse(response.body)
        raise Error, "OpenAI API error: #{extract_error_message(data, response)}" unless response.success?

        data
      end

      def extract_text(response_data)
        response_data.dig('choices', 0, 'message', 'content') || ''
      end

      def extract_error_message(data, response)
        data.dig('error', 'message') || "HTTP #{response.status}"
      end

      def connection
        @connection ||= Faraday.new(url: configuration.base_url) do |f|
          f.headers['Authorization'] = "Bearer #{configuration.api_key}"
          f.headers['content-type'] = 'application/json'
          f.options.timeout = 120
          f.options.open_timeout = 30
          f.adapter Faraday.default_adapter
        end
      end
    end
  end
end
