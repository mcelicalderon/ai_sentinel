# frozen_string_literal: true

require 'faraday'
require 'json'

module AiSentinel
  module Providers
    class Anthropic < Base
      API_VERSION = '2023-06-01'

      def chat(prompt:, system: nil, model: nil, workflow_name: nil, step_name: nil, remember: true,
               prompt_template: nil, system_template: nil, tool_executor: nil, max_tool_rounds: 10)
        model ||= configuration.model
        context_key = "#{workflow_name}:#{step_name}"

        response_data = with_context_retry(configuration.max_context_messages) do |ctx_limit|
          messages = build_messages(prompt, context_key, remember, limit: ctx_limit)

          if tool_executor
            run_tool_loop(messages, model, system, tool_executor, max_tool_rounds)
          else
            send_request(build_request_body(messages, model, system))
          end
        end

        assistant_text = extract_text(response_data)
        if remember
          save_context(context_key, prompt, assistant_text,
                       prompt_template: prompt_template, system_template: system_template)
        end

        Actions::AiPrompt::Result.new(
          response: assistant_text,
          model: response_data['model'],
          usage: response_data['usage']
        )
      end

      private

      def run_tool_loop(messages, model, system, tool_executor, max_tool_rounds)
        tools = tool_executor.tool_definitions_for(:anthropic)
        current_messages = messages.dup
        last_response = nil

        max_tool_rounds.times do |round|
          body = build_request_body(current_messages, model, system, tools: tools)
          last_response = send_request(body)

          break unless last_response['stop_reason'] == 'tool_use'

          tool_use_blocks = extract_tool_use_blocks(last_response)
          break if tool_use_blocks.empty?

          current_messages << { 'role' => 'assistant', 'content' => last_response['content'] }

          tool_results = tool_use_blocks.map do |tool_use|
            execute_tool_call(tool_executor, tool_use, round)
          end

          current_messages << { 'role' => 'user', 'content' => tool_results }
        end

        last_response
      end

      def execute_tool_call(tool_executor, tool_use, round)
        tool_name = tool_use['name']
        tool_input = tool_use['input']
        tool_id = tool_use['id']

        AiSentinel.logger.info("    Tool call [round #{round + 1}]: #{tool_name}(#{JSON.generate(tool_input)})")

        begin
          result = tool_executor.execute(tool_name, tool_input)
          AiSentinel.logger.info("    Tool result: #{result.to_s[0..200]}")
          { 'type' => 'tool_result', 'tool_use_id' => tool_id, 'content' => result.to_s }
        rescue Error => e
          AiSentinel.logger.warn("    Tool error: #{e.message}")
          { 'type' => 'tool_result', 'tool_use_id' => tool_id, 'content' => "Error: #{e.message}",
            'is_error' => true }
        end
      end

      def extract_tool_use_blocks(response_data)
        content = response_data['content'] || []
        content.select { |block| block['type'] == 'tool_use' }
      end

      def build_messages(prompt, context_key, remember, limit: nil)
        messages = []
        messages.concat(load_context(context_key, limit: limit)) if remember
        messages << { 'role' => 'user', 'content' => prompt }
        messages
      end

      def build_request_body(messages, model, system, tools: nil)
        body = { model: model, max_tokens: 4096, messages: messages }
        body[:system] = system if system
        body[:tools] = tools if tools
        body
      end

      def send_request(body)
        response = connection.post do |req|
          req.body = JSON.generate(body)
        end

        data = JSON.parse(response.body)

        unless response.success?
          message = extract_error_message(data, response)
          raise ContextOverflowError, message if context_overflow?(response, data)

          raise Error, "Anthropic API error: #{message}"
        end

        data
      end

      def context_overflow?(response, data)
        return true if response.status == 413

        response.status == 400 &&
          data.dig('error', 'type') == 'invalid_request_error' &&
          data.dig('error', 'message').to_s.match?(/too many tokens|token/i)
      end

      def extract_text(response_data)
        content = response_data['content'] || []
        text_blocks = content.select { |block| block['type'] == 'text' }
        text_blocks.map { |block| block['text'] }.join("\n")
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
