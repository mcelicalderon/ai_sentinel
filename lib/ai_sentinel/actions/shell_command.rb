# frozen_string_literal: true

require 'open3'
require 'timeout'

module AiSentinel
  module Actions
    class ShellCommand < Base
      Result = Struct.new(:stdout, :stderr, :exit_code, :success, keyword_init: true)

      def call
        command = interpolate(step.params[:command])
        timeout = step.params.fetch(:timeout, 30)

        stdout, stderr, status = execute_with_timeout(command, timeout)

        Result.new(stdout: stdout, stderr: stderr, exit_code: status.exitstatus, success: status.success?)
      end

      private

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
