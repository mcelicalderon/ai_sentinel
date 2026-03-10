# AiSentinel

[![Gem Version](https://badge.fury.io/rb/ai_sentinel.svg?icon=si%3Arubygems)](https://badge.fury.io/rb/ai_sentinel)

A lightweight Ruby gem for scheduling AI-driven tasks. Define workflows in a YAML config file that run on a cron schedule, process data through LLMs, and take conditional actions based on the results. Designed to be self-hostable on minimal hardware -- just Ruby and SQLite.

## Table of contents

- [Features](#features)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Configuration](#configuration)
  - [Global settings](#global-settings)
  - [Providers](#providers)
  - [Workflow definition](#workflow-definition)
  - [Full example](#full-example)
- [Actions](#actions)
  - [`http_get`](#http_get)
  - [`http_post`](#http_post)
  - [`ai_prompt`](#ai_prompt)
  - [`shell_command`](#shell_command)
- [Template interpolation](#template-interpolation)
- [Conditions](#conditions)
- [CLI](#cli)
  - [Daemon mode](#daemon-mode)
- [Tool use (AI agent autonomy)](#tool-use-ai-agent-autonomy)
  - [How tool use works](#how-tool-use-works)
  - [Available tools](#available-tools)
  - [Tool safety](#tool-safety)
  - [Allowed commands (allowlist)](#allowed-commands-allowlist)
- [Conversation memory](#conversation-memory)
  - [Memory and tool use](#memory-and-tool-use)
  - [Context compaction](#context-compaction)
  - [Custom compaction prompt](#custom-compaction-prompt)
  - [Prompt change detection](#prompt-change-detection)
  - [Token overflow recovery](#token-overflow-recovery)
- [Error handling](#error-handling)
- [Logging](#logging)
- [Development](#development)
- [License](#license)

## Features

- **YAML configuration** -- define workflows, steps, and conditions in a simple config file
- **Cron-based scheduling** via [rufus-scheduler](https://github.com/jmettraux/rufus-scheduler)
- **Multiple LLM providers** -- Anthropic Claude and OpenAI (plus any OpenAI-compatible API)
- **Persistent conversation context** -- the AI remembers previous interactions across runs (stored in SQLite)
- **Automatic context compaction** -- hierarchical summarization keeps context within token limits
- **Prompt change detection** -- detects when prompt templates change and lets you decide what to do with existing context
- **Token overflow recovery** -- automatic retry with reduced context on API token limit errors
- **AI agent tool use** -- give the AI autonomous shell access to inspect, analyze, and act on the local machine
- **Tool safety controls** -- command allowlist, subshell blocking, timeout, output truncation, working directory restriction
- **Conditional step execution** with `when` expressions
- **Template interpolation** -- pass data between steps with `{{step_name.field}}` syntax
- **Built-in actions**: HTTP GET/POST, AI prompts, shell commands
- **Config validation** -- catch errors before running
- **SSRF protection** -- blocks requests to private/loopback/link-local addresses
- **Shell injection protection** -- interpolated values are shell-escaped
- **File logging with rotation** -- optional log file output with automatic size-based rotation
- **Execution logging** -- full history of workflow runs and step results in SQLite
- **CLI** for starting, running, validating, and inspecting workflows
- **Environment variable support** via [dotenv](https://github.com/bkeepers/dotenv)

## Installation

Install the gem to make the `ai_sentinel` binary available system-wide:

```bash
gem install ai_sentinel
```

After installation, the `ai_sentinel` command is available in your `PATH`:

```bash
ai_sentinel version
```

> **Executable not found?** Ruby gems install binaries into a `bin/` directory that must be in your `PATH`. Run `gem environment` and look for the **EXECUTABLE DIRECTORY** value. Make sure that directory is in your `PATH`:
>
> ```bash
> # Check where gem binaries are installed
> gem environment | grep "EXECUTABLE DIRECTORY"
>
> # Add it to your shell profile if needed (~/.bashrc, ~/.zshrc, etc.)
> export PATH="$(gem environment gemdir)/bin:$PATH"
> ```
>
> If you use a Ruby version manager (asdf, rbenv, mise, chruby, rvm, etc.), gem binaries are typically added to your `PATH` automatically via shims. If the command still isn't found, run your version manager's reshim command (e.g., `asdf reshim ruby`, `rbenv rehash`).

### Bundler (for development or embedding in a project)

Add to your Gemfile:

```ruby
gem 'ai_sentinel'
```

Then run:

```bash
bundle install
```

When installed via Bundler, run commands with `bundle exec`:

```bash
bundle exec ai_sentinel version
```

## Quick start

### 1. Set your API key

**Option A: In the YAML config** (recommended for headless/embedded systems):

```yaml
global:
  api_key: sk-ant-...
```

**Option B: Via environment variable** (recommended for development):

Create a `.env` file in the directory where you'll run AiSentinel:

```bash
# For Anthropic
echo "ANTHROPIC_API_KEY=sk-ant-..." > .env

# For OpenAI
echo "OPENAI_API_KEY=sk-..." > .env
```

The YAML `api_key` takes priority. If not set, AiSentinel falls back to the environment variable for the configured provider (`ANTHROPIC_API_KEY` or `OPENAI_API_KEY`).

### 2. Generate a config file

```bash
ai_sentinel init
```

This creates `ai_sentinel.yml` with a sample workflow in the current directory.

### 3. Validate the config

```bash
ai_sentinel validate
```

### 4. Run a workflow manually

```bash
ai_sentinel run summarize_site
```

### 5. Start the scheduler

```bash
ai_sentinel start
```

Press `Ctrl+C` to stop.

### Using a custom config path

By default, AiSentinel looks for `ai_sentinel.yml` or `ai_sentinel.yaml` in the current directory. Use the `-c` flag to specify a different path:

```bash
ai_sentinel start -c /path/to/my_config.yml
ai_sentinel run my_workflow -c /path/to/my_config.yml
ai_sentinel validate -c /path/to/my_config.yml
```

## Configuration

All configuration is done in `ai_sentinel.yml`. API keys can be set in the YAML config or loaded from environment variables (via `.env` file or shell profile). The YAML `api_key` takes priority over the environment variable.

### Global settings

```yaml
global:
  api_key: sk-ant-...
  provider: anthropic
  model: claude-sonnet-4-6
  database: ./ai_sentinel.sqlite3
  max_context_messages: 50
  max_tool_rounds: 10
  compaction_threshold: 40
  compaction_buffer: 10
  on_prompt_change: ask
  working_directory: /opt/etc/ai_sentinel
  pid_file: /opt/var/run/ai_sentinel.pid
  log_file: ./logs/ai_sentinel.log
  log_file_size: 10485760
  log_files: 5
  base_url: http://localhost:11434/v1/chat/completions
  tool_safety:
    allowed_commands:
      - echo
      - ls
      - cat
      - grep
      - git
      - pwd
    working_directory: .
    tool_timeout: 30
    max_output_bytes: 10240
```

| Key | Default | Description |
|-----|---------|-------------|
| `api_key` | `nil` | API key for the configured provider. Takes priority over the environment variable. |
| `provider` | `anthropic` | LLM provider (`anthropic` or `openai`) |
| `model` | Provider-specific (see below) | Default model for AI steps |
| `database` | `~/.ai_sentinel/db.sqlite3` | SQLite database path |
| `max_context_messages` | `50` | Max conversation history per step |
| `max_tool_rounds` | `10` | Max tool-loop iterations per `ai_prompt` step (see [Tool use](#tool-use-ai-agent-autonomy)) |
| `compaction_threshold` | `40` | Message count that triggers automatic context compaction |
| `compaction_buffer` | `10` | Number of recent messages to keep verbatim after compaction |
| `on_prompt_change` | `ask` | Action when a prompt template changes (`ask`, `keep`, `drop`) |
| `working_directory` | `nil` | Working directory for the process. When set, the process `chdir`s to this directory on both `start` and `run`. Affects where relative file paths resolve (logs, database, files created by AI agents, shell command output). |
| `pid_file` | `~/.ai_sentinel/ai_sentinel.pid` | Path to the PID file written when running in daemon mode (`-d`). |
| `log_file` | `nil` (STDOUT) | Log file path. When omitted, logs go to STDOUT. |
| `log_file_size` | `10485760` (10 MB) | Max size per log file before rotation |
| `log_files` | `5` | Number of rotated log files to keep |
| `base_url` | Provider-specific (see below) | API endpoint URL |
| `tool_safety` | `nil` | Safety controls for AI-driven tool execution (see [Tool safety](#tool-safety)) |

### Providers

AiSentinel supports two providers out of the box. Each has sensible defaults:

| Provider | Default model | Default URL | Env var |
|----------|--------------|-------------|---------|
| `anthropic` | `claude-sonnet-4-6` | `https://api.anthropic.com/v1/messages` | `ANTHROPIC_API_KEY` |
| `openai` | `gpt-4o` | `https://api.openai.com/v1/chat/completions` | `OPENAI_API_KEY` |

#### Anthropic

```yaml
global:
  provider: anthropic
  model: claude-sonnet-4-6            # optional, this is the default
  api_key: sk-ant-...                # or set ANTHROPIC_API_KEY env var
```

#### OpenAI

```yaml
global:
  provider: openai
  model: gpt-4o                      # optional, this is the default
  api_key: sk-...                    # or set OPENAI_API_KEY env var
```

#### OpenAI-compatible APIs (Ollama, LM Studio, Azure, etc.)

Set `base_url` to point to any API that implements the OpenAI chat completions interface:

```yaml
global:
  provider: openai
  model: llama3
  base_url: http://localhost:11434/v1/chat/completions
```

### Workflow definition

Each workflow has a `schedule` (cron expression) and a list of `steps`:

```yaml
workflows:
  my_workflow:
    schedule: "*/5 * * * *"    # every 5 minutes
    steps:
      - id: step_name          # unique identifier
        action: http_get       # action type
        when: '...'            # optional condition
        params:                # action-specific parameters
          url: "https://..."
```

### Full example

```yaml
global:
  provider: anthropic
  model: claude-sonnet-4-6
  tool_safety:
    allowed_commands:
      - echo
      - ls
      - cat
      - grep
      - git
      - pwd
    tool_timeout: 30

workflows:
  check_prices:
    schedule: "0 9 * * *"
    steps:
      - id: fetch
        action: http_get
        params:
          url: "https://api.example.com/prices"

      - id: analyze
        action: ai_prompt
        params:
          prompt: "Analyze these prices for anomalies: {{fetch.body}}"

      - id: notify
        action: http_post
        when: '{{analyze.response}} contains "anomaly"'
        params:
          url: "https://hooks.slack.com/services/xxx"
          body:
            text: "Price alert: {{analyze.response}}"

  # AI agent with autonomous shell access
  code_reviewer:
    schedule: "0 9 * * *"
    steps:
      - id: review
        action: ai_prompt
        params:
          system: "You are a code reviewer. Use the shell_command tool to inspect the project."
          prompt: "Review recent git changes and suggest improvements."
          remember: true
          tools:
            - shell_command
          max_tool_rounds: 10
```

## Actions

Each action produces a result with specific fields. Use `{{step_id.field}}` in subsequent steps to reference these values (see [Template interpolation](#template-interpolation)).

### `http_get`

```yaml
- id: fetch
  action: http_get
  params:
    url: "https://api.example.com/data"
    headers:
      Authorization: "Bearer token"
```

**Result fields:**

| Field | Type | Description |
|-------|------|-------------|
| `status` | Integer | HTTP response status code (e.g. `200`, `404`) |
| `body` | String | Response body content |
| `headers` | Hash | Response headers |

### `http_post`

```yaml
- id: notify
  action: http_post
  params:
    url: "https://hooks.slack.com/services/xxx"
    body:
      text: "Alert: {{analyze.response}}"
    headers:
      Authorization: "Bearer token"
```

**Result fields:**

| Field | Type | Description |
|-------|------|-------------|
| `status` | Integer | HTTP response status code |
| `body` | String | Response body content |
| `headers` | Hash | Response headers |

### `ai_prompt`

```yaml
- id: analyze
  action: ai_prompt
  params:
    prompt: "Analyze this data: {{fetch.body}}"
    system: "You are a data analyst."
    model: gpt-4o
    remember: true
```

With tool use (AI agent autonomy):

```yaml
- id: review
  action: ai_prompt
  params:
    system: "You are a code reviewer. Use the shell_command tool to inspect files."
    prompt: "Review recent git changes and suggest improvements."
    remember: true
    tools:
      - shell_command
    max_tool_rounds: 10
```

**Params:**

| Param | Default | Description |
|-------|---------|-------------|
| `prompt` | (required) | The prompt to send to the LLM. Supports `{{step.field}}` interpolation. |
| `system` | `nil` | Optional system prompt. |
| `model` | Global default | Override the model for this step. |
| `remember` | `false` | When `true`, conversation history is persisted in SQLite and included in subsequent calls, enabling the AI to reference previous analyses across scheduled runs. |
| `tools` | `nil` | List of tools the AI can use autonomously during this step. See [Tool use](#tool-use-ai-agent-autonomy). |
| `max_tool_rounds` | `10` (global default) | Max number of tool-loop iterations for this step. Overrides the global `max_tool_rounds`. |
| `compaction_prompt` | `nil` | Custom system prompt for context compaction. When set, overrides the default generic summarization prompt for this step. See [Custom compaction prompt](#custom-compaction-prompt). |

**Result fields:**

| Field | Type | Description |
|-------|------|-------------|
| `response` | String | The AI-generated text (final response after all tool use) |
| `model` | String | Model name used for generation |
| `usage` | Hash | Token usage information |

### `shell_command`

> **Note**: This is the `shell_command` **action** -- a workflow step that runs a fixed command you define in the config. This is different from the `shell_command` **tool** (see [Tool use](#tool-use-ai-agent-autonomy)), which lets the AI autonomously decide what commands to run during an `ai_prompt` step.

```yaml
- id: check
  action: shell_command
  params:
    command: 'df -h / | tail -1'
    timeout: 30
```

Interpolated values in `shell_command` are automatically wrapped in single quotes to prevent shell injection. **Do not add your own quotes** around `{{...}}` placeholders — the escaping handles it:

```yaml
# Correct — no quotes around the placeholder
command: 'echo {{summarize.response}} > output.txt'

# Incorrect — extra quotes will appear in the output
command: 'echo "{{summarize.response}}" > output.txt'
```

**Result fields:**

| Field | Type | Description |
|-------|------|-------------|
| `stdout` | String | Standard output |
| `stderr` | String | Standard error |
| `exit_code` | Integer | Process exit code (`0` on success) |
| `success` | Boolean | `true` if the command exited with code `0` |

## Template interpolation

Use `{{step_id.field}}` to reference result fields from previous steps. The step id comes from the `id` you defined in the workflow, and the field must be one of the result fields listed above for that action type.

```yaml
- id: summarize
  action: ai_prompt
  params:
    prompt: "Status: {{check.stdout}}, Exit: {{check.exit_code}}"
```

**Quick reference:**

| Action | Available fields |
|--------|-----------------|
| `http_get` | `status`, `body`, `headers` |
| `http_post` | `status`, `body`, `headers` |
| `ai_prompt` | `response`, `model`, `usage` |
| `shell_command` | `stdout`, `stderr`, `exit_code`, `success` |

If a referenced step hasn't run yet (e.g. it was skipped by a `when` condition), the `{{...}}` placeholder is left in the string unchanged. All interpolated values are converted to strings via `.to_s`. In `shell_command` steps, interpolated values are automatically wrapped in single quotes to prevent shell injection — do not add your own quotes around `{{...}}` placeholders in shell commands.

## Conditions

Use `when` to conditionally execute a step. The condition is evaluated after template interpolation, so you can reference result fields from previous steps.

**Available operators:**

| Operator | Description | Example |
|----------|-------------|---------|
| `==` | Equality | `'{{fetch.status}} == 200'` |
| `!=` | Inequality | `'{{fetch.status}} != 200'` |
| `>` | Greater than (numeric) | `'{{fetch.status}} > 299'` |
| `>=` | Greater than or equal (numeric) | `'{{fetch.status}} >= 400'` |
| `<` | Less than (numeric) | `'{{fetch.status}} < 300'` |
| `<=` | Less than or equal (numeric) | `'{{fetch.status}} <= 299'` |
| `contains` | String includes substring | `'{{analyze.response}} contains "anomaly"'` |
| `not_contains` | String does not include substring | `'{{check.stderr}} not_contains "error"'` |

String values on the right side can be wrapped in double or single quotes. Numeric comparisons convert both sides to floats. If the expression doesn't match any operator pattern, it is evaluated as truthy (anything other than empty string, `0`, `false`, `nil`, or `null`).

## CLI

```
ai_sentinel start                    Start the scheduler
ai_sentinel start -d                 Start in daemon (background) mode
ai_sentinel stop                     Stop a running daemon
ai_sentinel run WORKFLOW             Manually trigger a workflow
ai_sentinel validate                 Validate config file
ai_sentinel list                     List workflows
ai_sentinel init                     Generate sample config
ai_sentinel history                  Show execution history
ai_sentinel history WORKFLOW         Filter by workflow
ai_sentinel history -n 50            Show last 50 entries
ai_sentinel context WF STEP          Show conversation context
ai_sentinel summary WF STEP          Show compacted context summary
ai_sentinel clear_context WF STEP    Clear context and summaries
ai_sentinel version                  Show version
ai_sentinel -v                       Show version

# Use a custom config path (works with any command)
ai_sentinel start -c path/to/config.yml
ai_sentinel stop -c path/to/config.yml
ai_sentinel run my_workflow -c path/to/config.yml
```

### Daemon mode

Use `-d` to run AiSentinel as a background daemon:

```bash
ai_sentinel start -d -c /path/to/config.yml
```

This detaches the process, writes a PID file (see `pid_file` in [Global settings](#global-settings)), and continues running in the background. Stop it with:

```bash
ai_sentinel stop -c /path/to/config.yml
```

The `stop` command reads the PID file, sends a `TERM` signal for graceful shutdown, and cleans up. If the PID file is stale (process already dead), it is removed automatically.

When `working_directory` is configured, the daemon changes to that directory before starting. This controls where relative file paths resolve -- useful for headless systems where the init system may start the process from an unpredictable directory.

## Tool use (AI agent autonomy)

AiSentinel can give the AI autonomous access to tools, allowing it to perform actions on the local machine as part of responding to a prompt. This is the same mechanism that powers coding assistants like Cursor, Copilot, and opencode -- the AI decides when and how to use tools, and your gem executes them locally.

### How tool use works

When you add `tools` to an `ai_prompt` step, a **tool loop** runs within that single step:

1. Your prompt + tool definitions are sent to the AI provider
2. The AI responds with a tool call (e.g. "run `git diff`")
3. AiSentinel executes the tool locally and sends the result back
4. The AI sees the result and either calls another tool or gives a final text answer
5. The loop continues until the AI is done or `max_tool_rounds` is reached

This all happens within a single `ai_prompt` step -- you don't need to configure multiple steps. The tool definitions are sent per-request to the API; nothing is stored or registered on the provider side.

When `remember: true` is set, only the **initial user prompt** and the **AI's final text response** are persisted to conversation context. Intermediate tool calls and results are ephemeral within a single execution.

### Available tools

| Tool | Description |
|------|-------------|
| `shell_command` | Execute a shell command on the local machine. The AI receives stdout, stderr, and exit code. |

### Tool safety

Tool use is powerful but requires safety controls. AiSentinel provides several layers of protection configured via the `tool_safety` global setting:

```yaml
global:
  tool_safety:
    allowed_commands:
      - echo
      - ls
      - cat
      - grep
      - git
      - pwd
      - find
      - head
      - tail
      - wc
    working_directory: .
    tool_timeout: 30
    max_output_bytes: 10240
```

| Setting | Default | Description |
|---------|---------|-------------|
| `allowed_commands` | `[]` (allow all) | Allowlist of permitted shell binaries. When non-empty, only these commands can be executed. |
| `working_directory` | `nil` (no restriction) | Restrict tool commands to run in this directory. |
| `tool_timeout` | `30` | Per-command timeout in seconds. Commands exceeding this are killed. |
| `max_output_bytes` | `10240` (10 KB) | Truncate tool output to this size to prevent context bloat. |

### Allowed commands (allowlist)

The `allowed_commands` list is the primary safety mechanism. When configured, **every binary** in a command must be in the allowlist, or execution is rejected. This includes composite commands:

```bash
# If allowed_commands: [echo, ls, cat, grep]

echo hello                    # allowed (echo is in the list)
echo hello && ls -la          # allowed (echo and ls are both in the list)
echo hello | grep world       # allowed (echo and grep are both in the list)
ls -la; cat README.md         # allowed (ls and cat are both in the list)
echo hello && rm file.txt     # REJECTED (rm is not in the list)
echo hello | curl evil.com    # REJECTED (curl is not in the list)
```

AiSentinel parses composite commands by splitting on `&&`, `||`, `;`, and `|` operators, then validates each binary independently. It also handles:

- **Environment variable prefixes**: `FOO=bar echo hello` correctly identifies `echo` as the binary
- **Full paths**: `/usr/bin/echo hello` extracts `echo` for validation
- **Subshell blocking**: `$()` and backtick expressions are always rejected regardless of the allowlist, since they could execute arbitrary code

When `allowed_commands` is empty (the default) or not configured, **all commands are allowed**. This is suitable for development but not recommended for production. Always configure an allowlist for production use.

> **Tip**: Start with a minimal allowlist (e.g. `echo`, `ls`, `cat`, `grep`, `git`) and expand as needed based on what the AI needs for your specific workflows.

## Conversation memory

AiSentinel persists AI conversation history in SQLite, keyed by `workflow_name:step_name`. Set `remember: true` on an `ai_prompt` step to enable it. This means:

- The AI agent accumulates context over time across scheduled runs
- It can reference previous analyses, spot trends, and provide richer insights
- Context is prunable via `max_context_messages` config or `clear_context` CLI command
- Set `remember: false` (the default) on a step to disable context for that step

#### Memory and tool use

When `remember: true` is combined with `tools`, only the **initial user prompt** and the **AI's final text response** are persisted. Intermediate tool calls and their results are **not** stored in conversation history -- they are ephemeral within a single execution.

This means the AI remembers *what it concluded* across runs, but not the exact tool calls it made. For example, if the AI ran `echo "entry" >> log.txt` in a previous run, it won't remember the exact command, but it will remember from its own response that it logged an entry. This keeps the stored context clean and avoids bloating the database with tool call details.

### Context compaction

As conversation history grows, AiSentinel automatically compacts it using hierarchical summarization to stay within token limits. This uses two tiers:

1. **Long-term summary** -- a running summary of older conversations, updated incrementally via an LLM call
2. **Short-term buffer** -- the most recent messages kept verbatim for full fidelity

When the message count for a step reaches `compaction_threshold` (default 40):
- The oldest messages (all except the `compaction_buffer` most recent) are sent to the LLM along with any existing summary
- The LLM produces an updated summary combining old and new information
- The summarized messages are deleted and replaced with the new summary in the database
- Subsequent API calls receive: `[summary]` + `[recent verbatim messages]` + `[new prompt]`

This happens automatically and transparently. The summarization call uses the same provider/model configured globally and does not pollute the step's own conversation history.

Configure via `ai_sentinel.yml`:

```yaml
global:
  compaction_threshold: 40    # trigger compaction at this message count
  compaction_buffer: 10       # keep this many recent messages verbatim
```

Inspect the current summary with:

```bash
ai_sentinel summary my_workflow my_step
```

### Custom compaction prompt

By default, context compaction uses a generic summarization prompt. For domain-specific workflows (e.g., trading agents, monitoring systems), the default prompt may not preserve the right information. Use `compaction_prompt` on an `ai_prompt` step to provide a custom summarization instruction:

```yaml
- id: trade_cycle
  action: ai_prompt
  params:
    prompt: "Execute a trading cycle. {{fetch.stdout}}"
    remember: true
    compaction_prompt: |
      Summarize the trading history below. Preserve: exact entry prices,
      fill quantities, fees, position status, cycle count, cumulative P&L,
      and any adaptive behavior notes. Drop old market data.
    tools:
      - shell_command
```

The custom prompt replaces the system prompt in the compaction LLM call. The user prompt (containing the messages to summarize) is built the same way as the default compaction. When `compaction_prompt` is not set, the default generic summarization prompt is used.

### Prompt change detection

AiSentinel tracks a SHA256 hash of each step's prompt and system templates. When you modify a prompt template in `ai_sentinel.yml`, AiSentinel detects the change on the next `start` or `run` and asks what to do with the existing conversation context, since it was built with a different prompt.

In interactive mode (the default), you'll see:

```
Prompt changed for 'my_workflow:analyze'.
  1. Keep existing context
  2. Clear context and start fresh
  3. Abort
  Choice [1/2/3]:
```

Whichever option you choose, the stored hash is updated so you won't be asked again until the prompt changes again.

For daemon mode (`-d`) or CI environments where there is no TTY, set `on_prompt_change` in the config:

```yaml
global:
  on_prompt_change: keep    # or 'drop' to auto-clear context on prompt changes
```

| Policy | Behavior |
|--------|----------|
| `ask` | Interactive prompt (default). Falls back to `keep` in daemon mode. |
| `keep` | Silently keep existing context and update the stored hash. |
| `drop` | Automatically clear context and summaries, then update the stored hash. |

### Token overflow recovery

If an API call exceeds the provider's token limit despite compaction, AiSentinel automatically retries with progressively fewer context messages (halved each attempt, up to 3 retries). This handles edge cases where individual messages are unusually large.

- **Anthropic**: detects HTTP 400 `invalid_request_error` with token-related messages, or HTTP 413 `request_too_large`
- **OpenAI**: detects HTTP 400 with `maximum context length`, `too many tokens`, or `context_length_exceeded` messages

## Error handling

AiSentinel logs errors with backtraces at every level to aid debugging, especially on headless systems:

- **Workflow failures** -- logged with full backtrace and recorded in the execution history database
- **Tool execution errors** -- caught and returned to the AI as error messages so the conversation can continue
- **Context compaction failures** -- logged but non-fatal; the step continues without compacting
- **Scheduler crashes** -- logged with backtrace before the process exits
- **Top-level errors** -- caught at the executable entry point to ensure errors are always logged, even for unexpected failures

When running in daemon mode, the PID file is automatically cleaned up on crashes via an `at_exit` hook.

## Logging

By default, AiSentinel logs to STDOUT. Set `log_file` to redirect logs to a file with automatic rotation:

```yaml
global:
  log_file: ./logs/ai_sentinel.log
  log_file_size: 10485760    # 10 MB per file (default)
  log_files: 5               # keep 5 rotated files (default)
```

When `log_file` is set, AiSentinel creates the directory if it doesn't exist and uses Ruby's built-in `Logger` rotation. When the active log file reaches `log_file_size`, it is renamed (e.g. `ai_sentinel.log.0`, `ai_sentinel.log.1`, ...) and a new file is started. The oldest file is deleted when `log_files` is exceeded.

Omit `log_file` (or leave it unset) to keep the default STDOUT behavior, which is useful for development and Docker/container environments where logs are captured from the process output.

## Development

```bash
bin/setup          # Install dependencies
bundle exec rspec  # Run tests
bundle exec rubocop # Run linter
bundle exec rake   # Run both
bin/console        # Interactive console
```

To install the gem locally for testing the CLI:

```bash
bundle exec rake install
ai_sentinel version
```

## License

The gem is available as open source under the terms of the [MIT License](LICENSE).
