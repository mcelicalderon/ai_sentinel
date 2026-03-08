# frozen_string_literal: true

require 'faraday'
require 'json'

module AiSentinel
  module Providers
    class Anthropic < Base
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
        raise Error, "Anthropic API error: #{extract_error_message(data, response)}" unless response.success?

        data
      end

      def extract_text(response_data)
        response_data.dig('content', 0, 'text') || ''
      end

      def extract_error_message(data, response)
        data.dig('error', 'message') || "HTTP #{response.status}"
      end

      def connection
        @connection ||= Faraday.new(url: configuration.base_url) do |f|
          f.headers['x-api-key'] = configuration.api_key
          f.headers['anthropic-version'] = API_VERSION
          f.headers['content-type'] = 'application/json'
          f.options.timeout = 120
          f.options.open_timeout = 30
          f.adapter Faraday.default_adapter
        end
      end
    end
  end
end
