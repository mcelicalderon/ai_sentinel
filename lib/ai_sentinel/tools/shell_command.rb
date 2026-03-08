# frozen_string_literal: true

require 'open3'
require 'timeout'

module AiSentinel
  module Tools
    class ShellCommand < Base
      def name
        'shell_command'
      end

      def description
        'Execute a shell command on the local machine. Returns stdout, stderr, and the exit code. ' \
          'Use this to run CLI tools, inspect files, manage processes, or perform any system operation.'
      end

      def input_schema
        {
          type: 'object',
          properties: {
            command: {
              type: 'string',
              description: 'The shell command to execute (e.g. "ls -la", "git status", "cat file.txt")'
            }
          },
          required: ['command']
        }
      end

      def execute(input)
        command = input['command'] || input[:command]
        raise Error, 'Missing required parameter: command' unless command
        raise Error, 'Command must be a non-empty string' if command.strip.empty?

        { stdout: '', stderr: '', exit_code: -1 }
      end
    end
  end
end
