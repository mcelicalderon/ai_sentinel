# frozen_string_literal: true

module AiSentinel
  class CLI < Thor
    module Helpers
      private

      def load_config
        loader = ConfigLoader.new(options[:config])
        loader.load!
      end

      def setup_database
        if options[:config]
          load_config
        elsif options[:db]
          Persistence::Database.setup(options[:db])
          return
        else
          begin
            load_config
          rescue ConfigurationError
            Persistence::Database.setup(AiSentinel.configuration.database_path)
            return
          end
        end
        Persistence::Database.setup(AiSentinel.configuration.database_path)
      end

      def result_summary(result)
        case result
        when Actions::AiPrompt::Result
          truncate(result.response, 100)
        when Actions::HttpGet::Result, Actions::HttpPost::Result
          "HTTP #{result.status} (#{result.body.length} bytes)"
        when Actions::ShellCommand::Result
          result.success ? 'exit 0' : "exit #{result.exit_code}"
        else
          result.to_s[0..100]
        end
      end

      def truncate(text, length)
        return text if text.length <= length

        "#{text[0...length]}..."
      end

      def colorize_status(status)
        case status
        when 'completed' then "\e[32m#{status}\e[0m"
        when 'failed'    then "\e[31m#{status}\e[0m"
        when 'running'   then "\e[33m#{status}\e[0m"
        else status
        end
      end

      def sample_config
        <<~YAML
          # ai_sentinel.yml
          # See https://github.com/mcelicalderon/ai_sentinel for documentation.

          global:
            provider: anthropic
            model: claude-sonnet-4-20250514
            # database: ./ai_sentinel.sqlite3
            # max_context_messages: 50

          workflows:
            example:
              schedule: "*/5 * * * *"
              steps:
                - id: fetch
                  action: http_get
                  params:
                    url: "https://example.com"

                - id: summarize
                  action: ai_prompt
                  params:
                    system: "You are a concise technical writer."
                    prompt: "Summarize this content in 2-3 sentences: {{fetch.body}}"
                    remember: false
        YAML
      end
    end
  end
end
