# AiSentinel

A lightweight Ruby gem for scheduling AI-driven tasks. Define workflows in a YAML config file that run on a cron schedule, process data through LLMs, and take conditional actions based on the results. Designed to be self-hostable on minimal hardware -- just Ruby and SQLite.

## Features

- **YAML configuration** -- define workflows, steps, and conditions in a simple config file
- **Cron-based scheduling** via [rufus-scheduler](https://github.com/jmettraux/rufus-scheduler)
- **Multiple LLM providers** -- Anthropic Claude and OpenAI (plus any OpenAI-compatible API)
- **Persistent conversation context** -- the AI remembers previous interactions across runs (stored in SQLite)
- **Automatic context compaction** -- hierarchical summarization keeps context within token limits
- **Token overflow recovery** -- automatic retry with reduced context on API token limit errors
- **Conditional step execution** with `when` expressions
- **Template interpolation** -- pass data between steps with `{{step_name.field}}` syntax
- **Built-in actions**: HTTP GET/POST, AI prompts, shell commands
- **Config validation** -- catch errors before running
- **SSRF protection** -- blocks requests to private/loopback/link-local addresses
- **Shell injection protection** -- interpolated values are shell-escaped
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

Create a `.env` file in the directory where you'll run AiSentinel:

```bash
# For Anthropic
echo "ANTHROPIC_API_KEY=sk-ant-..." > .env

# For OpenAI
echo "OPENAI_API_KEY=sk-..." > .env
```

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

All configuration is done in `ai_sentinel.yml`. API keys are loaded from environment variables (via `.env` file). **Never put API keys in the YAML config.**

### Global settings

```yaml
global:
  provider: anthropic
  model: claude-sonnet-4-20250514
  database: ./ai_sentinel.sqlite3
  max_context_messages: 50
  compaction_threshold: 40
  compaction_buffer: 10
  base_url: http://localhost:11434/v1/chat/completions
```

| Key | Default | Description |
|-----|---------|-------------|
| `provider` | `anthropic` | LLM provider (`anthropic` or `openai`) |
| `model` | Provider-specific (see below) | Default model for AI steps |
| `database` | `~/.ai_sentinel/db.sqlite3` | SQLite database path |
| `max_context_messages` | `50` | Max conversation history per step |
| `compaction_threshold` | `40` | Message count that triggers automatic context compaction |
| `compaction_buffer` | `10` | Number of recent messages to keep verbatim after compaction |
| `base_url` | Provider-specific (see below) | API endpoint URL |

### Providers

AiSentinel supports two providers out of the box. Each has sensible defaults:

| Provider | Default model | Default URL | Env var |
|----------|--------------|-------------|---------|
| `anthropic` | `claude-sonnet-4-20250514` | `https://api.anthropic.com/v1/messages` | `ANTHROPIC_API_KEY` |
| `openai` | `gpt-4o` | `https://api.openai.com/v1/chat/completions` | `OPENAI_API_KEY` |

#### Anthropic

```yaml
global:
  provider: anthropic
  model: claude-sonnet-4-20250514    # optional, this is the default
```

```bash
echo "ANTHROPIC_API_KEY=sk-ant-..." > .env
```

#### OpenAI

```yaml
global:
  provider: openai
  model: gpt-4o                      # optional, this is the default
```

```bash
echo "OPENAI_API_KEY=sk-..." > .env
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
  model: claude-sonnet-4-20250514

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
```

## Actions

### `http_get`

```yaml
- id: fetch
  action: http_get
  params:
    url: "https://api.example.com/data"
    headers:
      Authorization: "Bearer token"
```

Returns: `status`, `body`, `headers`

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

Returns: `status`, `body`, `headers`

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

Returns: `response`, `model`, `usage`

| Param | Default | Description |
|-------|---------|-------------|
| `prompt` | (required) | The prompt to send to the LLM. Supports `{{step.field}}` interpolation. |
| `system` | `nil` | Optional system prompt. |
| `model` | Global default | Override the model for this step. |
| `remember` | `false` | When `true`, conversation history is persisted in SQLite and included in subsequent calls, enabling the AI to reference previous analyses across scheduled runs. |

### `shell_command`

```yaml
- id: check
  action: shell_command
  params:
    command: 'df -h / | tail -1'
    timeout: 30
```

Returns: `stdout`, `stderr`, `exit_code`, `success`

## Conditions

Use `when` to conditionally execute a step. Supports comparisons and string matching:

```yaml
# Equality
when: '{{fetch.status}} == 200'

# Inequality
when: '{{fetch.status}} != 200'

# Numeric comparisons
when: '{{fetch.status}} >= 400'

# String contains
when: '{{analyze.response}} contains "anomaly"'

# String does not contain
when: '{{check.stderr}} not_contains "error"'
```

## Template interpolation

Use `{{step_id.field}}` to reference results from previous steps:

```yaml
- id: summarize
  action: ai_prompt
  params:
    prompt: "Status: {{check.stdout}}, Exit: {{check.exit_code}}"
```

## CLI

```
ai_sentinel start                    Start the scheduler
ai_sentinel start -d                 Start in background mode
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
ai_sentinel run my_workflow -c path/to/config.yml
```

## Conversation memory

AiSentinel persists AI conversation history in SQLite, keyed by `workflow_name:step_name`. Set `remember: true` on an `ai_prompt` step to enable it. This means:

- The AI agent accumulates context over time across scheduled runs
- It can reference previous analyses, spot trends, and provide richer insights
- Context is prunable via `max_context_messages` config or `clear_context` CLI command
- Set `remember: false` (the default) on a step to disable context for that step

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

### Token overflow recovery

If an API call exceeds the provider's token limit despite compaction, AiSentinel automatically retries with progressively fewer context messages (halved each attempt, up to 3 retries). This handles edge cases where individual messages are unusually large.

- **Anthropic**: detects HTTP 400 `invalid_request_error` with token-related messages, or HTTP 413 `request_too_large`
- **OpenAI**: detects HTTP 400 with `maximum context length`, `too many tokens`, or `context_length_exceeded` messages

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
