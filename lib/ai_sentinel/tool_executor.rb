# frozen_string_literal: true

require 'open3'
require 'shellwords'
require 'timeout'

module AiSentinel
  class ToolExecutor
    SUBSHELL_PATTERN = /\$\(|`/
    DEFAULT_TIMEOUT = 30
    DEFAULT_MAX_OUTPUT_BYTES = 10_240
    DEFAULT_MAX_TOOL_ROUNDS = 10

    attr_reader :tools, :configuration

    def initialize(tools:, configuration:)
      @tools = tools.to_h { |t| [t.name, t] }
      @configuration = configuration
    end

    def tool_definitions_for(provider)
      @tools.values.map do |tool|
        case provider
        when :anthropic then tool.to_anthropic_schema
        when :openai then tool.to_openai_schema
        else raise Error, "Unknown provider for tool schema: #{provider}"
        end
      end
    end

    def execute(tool_name, input)
      tool = @tools[tool_name]
      raise Error, "Unknown tool: #{tool_name}" unless tool

      case tool_name
      when 'shell_command'
        execute_shell_command(input)
      else
        tool.execute(input)
      end
    end

    def max_tool_rounds
      configuration.respond_to?(:max_tool_rounds) ? configuration.max_tool_rounds : DEFAULT_MAX_TOOL_ROUNDS
    end

    private

    def execute_shell_command(input)
      command = input['command'] || input[:command]
      raise Error, 'Missing required parameter: command' unless command
      raise Error, 'Command must be a non-empty string' if command.to_s.strip.empty?

      validate_command!(command)

      timeout = tool_timeout
      max_bytes = max_output_bytes

      stdout, stderr, status = run_with_timeout(command, timeout)

      stdout = truncate_output(stdout, max_bytes)
      stderr = truncate_output(stderr, max_bytes)

      JSON.generate(stdout: stdout, stderr: stderr, exit_code: status.exitstatus)
    rescue Timeout::Error
      JSON.generate(stdout: '', stderr: "Command timed out after #{timeout}s", exit_code: -1)
    end

    def validate_command!(command)
      validate_no_subshells!(command)
      binaries = extract_binaries(command)
      validate_allowlist!(binaries)
    end

    def validate_no_subshells!(command)
      return unless command.match?(SUBSHELL_PATTERN)

      raise Error, "Command contains subshell execution ($() or backticks) which is not allowed: #{command}"
    end

    def extract_binaries(command)
      segments = split_on_operators(command)

      segments.map do |segment|
        segment = segment.strip

        segment = segment.sub(/\A\s*(?:\w+=\S*\s+)*/, '')

        tokens = Shellwords.split(segment)
        next nil if tokens.empty?

        binary = tokens.first
        File.basename(binary)
      rescue ArgumentError
        raise Error, "Malformed command segment: #{segment}"
      end.compact
    end

    def split_on_operators(command)
      segments = []
      current = +''
      chars = command.chars
      i = 0
      quote = nil

      while i < chars.length
        char = chars[i]
        quote = toggle_quote(char, quote) if quote_boundary?(char, quote)

        if !quote && (skip = operator_length(chars, i))
          segments << current
          current = +''
          i += skip
        else
          current << char
          i += 1
        end
      end

      segments << current unless current.strip.empty?
      segments
    end

    def quote_boundary?(char, quote)
      ["'", '"'].include?(char) && (quote.nil? || quote == char)
    end

    def toggle_quote(char, quote)
      quote == char ? nil : char
    end

    def operator_length(chars, index)
      two_char = "#{chars[index]}#{chars[index + 1]}"
      return 2 if ['&&', '||'].include?(two_char)
      return 1 if [';', '|'].include?(chars[index])

      nil
    end

    def validate_allowlist!(binaries)
      allowed = allowed_commands
      return if allowed.empty?

      binaries.each do |binary|
        next if allowed.include?(binary)

        raise Error,
              "Command '#{binary}' is not in the allowed commands list. " \
              "Allowed: #{allowed.join(', ')}"
      end
    end

    def allowed_commands
      safety = configuration.tool_safety
      return [] unless safety

      safety[:allowed_commands] || safety['allowed_commands'] || []
    end

    def tool_timeout
      safety = configuration.tool_safety
      return DEFAULT_TIMEOUT unless safety

      safety[:tool_timeout] || safety['tool_timeout'] || DEFAULT_TIMEOUT
    end

    def max_output_bytes
      safety = configuration.tool_safety
      return DEFAULT_MAX_OUTPUT_BYTES unless safety

      safety[:max_output_bytes] || safety['max_output_bytes'] || DEFAULT_MAX_OUTPUT_BYTES
    end

    def working_directory
      safety = configuration.tool_safety
      return nil unless safety

      dir = safety[:working_directory] || safety['working_directory']
      dir ? File.expand_path(dir) : nil
    end

    def run_with_timeout(command, timeout)
      opts = {}
      dir = working_directory
      opts[:chdir] = dir if dir

      Timeout.timeout(timeout) do
        Open3.capture3(command, **opts)
      end
    end

    def truncate_output(output, max_bytes)
      return output if output.bytesize <= max_bytes

      truncated = output.byteslice(0, max_bytes)
      "#{truncated}\n... [truncated at #{max_bytes} bytes]"
    end
  end
end
