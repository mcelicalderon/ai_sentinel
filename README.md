# AiSentinel

A lightweight Ruby gem for scheduling AI-driven tasks. Define workflows in a YAML config file that run on a cron schedule, process data through LLMs, and take conditional actions based on the results. Designed to be self-hostable on minimal hardware -- just Ruby and SQLite.

## Features

- **YAML configuration** -- define workflows, steps, and conditions in a simple config file
- **Cron-based scheduling** via [rufus-scheduler](https://github.com/jmettraux/rufus-scheduler)
- **AI-powered steps** using the Anthropic Claude API
- **Persistent conversation context** -- the AI remembers previous interactions across runs (stored in SQLite)
- **Conditional step execution** with `when` expressions
- **Template interpolation** -- pass data between steps with `{{step_name.field}}` syntax
- **Built-in actions**: HTTP GET/POST, AI prompts, shell commands
- **Config validation** -- catch errors before running
- **Execution logging** -- full history of workflow runs and step results in SQLite
- **CLI** for starting, running, validating, and inspecting workflows
- **Environment variable support** via [dotenv](https://github.com/bkeepers/dotenv)

## Installation

```bash
gem install ai_sentinel
```

Or add to your Gemfile:

```ruby
gem 'ai_sentinel'
```

## Quick Start

### 1. Set your API key

```bash
echo "ANTHROPIC_API_KEY=sk-ant-..." > .env
```

### 2. Generate a config file

```bash
ai_sentinel init
```

This creates `ai_sentinel.yml` with a sample workflow.

### 3. Validate the config

```bash
ai_sentinel validate
```

### 4. Run a workflow manually

```bash
ai_sentinel run example
```

### 5. Start the scheduler

```bash
ai_sentinel start
```

Press Ctrl+C to stop.

## Configuration

All configuration is done in `ai_sentinel.yml` (or specify a path with `-c`).

```yaml
global:
  provider: anthropic
  model: claude-sonnet-4-20250514
  database: ./ai_sentinel.sqlite3
  max_context_messages: 50

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

### Global settings

| Key | Default | Description |
|-----|---------|-------------|
| `provider` | `anthropic` | LLM provider |
| `model` | `claude-sonnet-4-20250514` | Default model |
| `database` | `~/.ai_sentinel/db.sqlite3` | SQLite database path |
| `max_context_messages` | `50` | Max conversation history per step |

API keys are loaded from environment variables (via `.env` file). **Never put API keys in the YAML config.**

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
    model: claude-sonnet-4-20250514
    remember: true
```

Returns: `response`, `model`, `usage`

When `remember: true` (default), conversation history is stored in SQLite and included in subsequent calls, so the AI can reference previous analyses across scheduled runs.

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

## Template Interpolation

Use `{{step_id.field}}` to reference results from previous steps:

```yaml
- id: summarize
  action: ai_prompt
  params:
    prompt: "Status: {{check.stdout}}, Exit: {{check.exit_code}}"
```

## CLI

```bash
ai_sentinel start                # Start the scheduler
ai_sentinel start -d             # Start in background mode
ai_sentinel run WORKFLOW         # Manually trigger a workflow
ai_sentinel validate             # Validate config file
ai_sentinel list                 # List workflows
ai_sentinel init                 # Generate sample config
ai_sentinel history              # Show execution history
ai_sentinel history WORKFLOW     # Filter by workflow
ai_sentinel context WF STEP     # Show conversation context
ai_sentinel clear_context WF STEP  # Clear conversation context
ai_sentinel version              # Show version

# Use a custom config path
ai_sentinel start -c path/to/config.yml
```

## Conversation Memory

AiSentinel persists AI conversation history in SQLite, keyed by `workflow_name:step_name`. This means:

- The AI agent accumulates context over time across scheduled runs
- It can reference previous analyses, spot trends, and provide richer insights
- Context is prunable via `max_context_messages` config or `clear_context` CLI command
- Set `remember: false` on a step to disable context for that step

## Development

```bash
bin/setup          # Install dependencies
bundle exec rspec  # Run tests
bundle exec rubocop # Run linter
bundle exec rake   # Run both
bin/console        # Interactive console
```

## License

The gem is available as open source under the terms of the [MIT License](LICENSE).
