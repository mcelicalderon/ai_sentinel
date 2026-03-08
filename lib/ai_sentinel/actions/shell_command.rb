# frozen_string_literal: true

require 'open3'
require 'shellwords'
require 'timeout'

module AiSentinel
  module Actions
    class ShellCommand < Base
      Result = Struct.new(:stdout, :stderr, :exit_code, :success, keyword_init: true)

      def call
        command = safe_interpolate(step.params[:command])
        timeout = step.params.fetch(:timeout, 30)

        stdout, stderr, status = execute_with_timeout(command, timeout)

        Result.new(stdout: stdout, stderr: stderr, exit_code: status.exitstatus, success: status.success?)
      end

      private

      def safe_interpolate(template)
        return template unless template.is_a?(String)

        template.gsub(/\{\{(\w+)\.(\w+)\}\}/) do
          step_name = ::Regexp.last_match(1).to_sym
          field = ::Regexp.last_match(2).to_sym
          step_result = context[step_name]
          next "{{#{::Regexp.last_match(1)}.#{::Regexp.last_match(2)}}}" unless step_result

          raw = step_result.respond_to?(field) ? step_result.public_send(field).to_s : step_result.to_s
          Shellwords.escape(raw)
        end
      end

      def execute_with_timeout(command, timeout)
        Timeout.timeout(timeout) do
          Open3.capture3(command)
        end
      rescue Timeout::Error
        raise Error, "Shell command timed out after #{timeout}s: #{command}"
      end
    end
  end
end
