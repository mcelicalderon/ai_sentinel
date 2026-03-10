# frozen_string_literal: true

require 'faraday'
require 'json'

module AiSentinel
  module Providers
    class Openai < Base
      def chat(prompt:, system: nil, model: nil, workflow_name: nil, step_name: nil, remember: true,
               prompt_template: nil, system_template: nil, tool_executor: nil, max_tool_rounds: 10,
               compaction_prompt: nil)
        model ||= configuration.model
        context_key = "#{workflow_name}:#{step_name}"

        response_data = with_context_retry(configuration.max_context_messages) do |ctx_limit|
          messages = build_messages(prompt, system, context_key, remember, limit: ctx_limit)

          if tool_executor
            run_tool_loop(messages, model, tool_executor, max_tool_rounds)
          else
            send_request(messages, model)
          end
        end

        assistant_text = extract_text(response_data)
        if remember
          save_context(context_key, prompt, assistant_text,
                       prompt_template: prompt_template, system_template: system_template,
                       compaction_prompt: compaction_prompt)
        end

        Actions::AiPrompt::Result.new(
          response: assistant_text,
          model: response_data['model'],
          usage: response_data['usage']
        )
      end

      private

      def run_tool_loop(messages, model, tool_executor, max_tool_rounds)
        tools = tool_executor.tool_definitions_for(:openai)
        current_messages = messages.dup
        last_response = nil

        max_tool_rounds.times do |round|
          last_response = send_request_with_tools(current_messages, model, tools)

          tool_calls = last_response.dig('choices', 0, 'message', 'tool_calls')
          break unless tool_calls&.any?

          current_messages << last_response.dig('choices', 0, 'message')

          tool_calls.each do |tool_call|
            result = execute_tool_call(tool_executor, tool_call, round)
            current_messages << result
          end
        end

        last_response
      end

      def execute_tool_call(tool_executor, tool_call, round)
        function = tool_call['function']
        tool_name = function['name']
        tool_id = tool_call['id']

        AiSentinel.logger.info("    Tool call [round #{round + 1}]: #{tool_name}(#{function['arguments']})")

        tool_input = JSON.parse(function['arguments'])
        result = tool_executor.execute(tool_name, tool_input)
        AiSentinel.logger.info("    Tool result: #{result.to_s[0..200]}")
        { 'role' => 'tool', 'tool_call_id' => tool_id, 'content' => result.to_s }
      rescue StandardError => e
        AiSentinel.log_error(e, context: "Tool '#{tool_name}' error")
        { 'role' => 'tool', 'tool_call_id' => tool_id, 'content' => "Error: #{e.message}" }
      end

      def build_messages(prompt, system, context_key, remember, limit: nil)
        messages = []
        messages << { 'role' => 'system', 'content' => system } if system
        messages.concat(load_context(context_key, limit: limit)) if remember
        messages << { 'role' => 'user', 'content' => prompt }
        messages
      end

      def send_request(messages, model)
        body = { model: model, messages: messages }
        post_request(body)
      end

      def send_request_with_tools(messages, model, tools)
        body = { model: model, messages: messages, tools: tools }
        post_request(body)
      end

      def post_request(body)
        response = connection.post do |req|
          req.body = JSON.generate(body)
        end

        data = JSON.parse(response.body)

        unless response.success?
          message = extract_error_message(data, response)
          raise ContextOverflowError, message if context_overflow?(response, data)

          raise Error, "OpenAI API error: #{message}"
        end

        data
      end

      def context_overflow?(response, data)
        response.status == 400 &&
          data.dig('error', 'message').to_s.match?(/maximum context length|too many tokens|context_length_exceeded/i)
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
