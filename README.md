# AiSentinel

A lightweight Ruby gem for scheduling AI-driven tasks. Define workflows that run on a cron schedule, process data through LLMs, and take conditional actions based on the results. Designed to be self-hostable on minimal hardware -- just Ruby and SQLite.

## Features

- **Cron-based scheduling** via [rufus-scheduler](https://github.com/jmettraux/rufus-scheduler)
- **AI-powered steps** using the Anthropic Claude API
- **Persistent conversation context** -- the AI remembers previous interactions across runs (stored in SQLite)
- **Conditional step execution** -- skip steps based on previous results
- **Template interpolation** -- pass data between steps with `{{step_name.field}}` syntax
- **Built-in actions**: HTTP GET/POST, AI prompts, shell commands
- **Execution logging** -- full history of workflow runs and step results in SQLite
- **CLI** for starting, listing, running, and inspecting workflows
- **Environment variable support** via [dotenv](https://github.com/bkeepers/dotenv)

## Installation

Add to your Gemfile:

```ruby
gem 'ai_sentinel'
```

Or install directly:

```bash
gem install ai_sentinel
```

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and set your API key:

```bash
cp .env.example .env
```

```env
ANTHROPIC_API_KEY=your-api-key-here
```

The `.env` file is automatically loaded via dotenv. **Never commit `.env` to version control.**

### Ruby Configuration

```ruby
AiSentinel.configure do |config|
  config.provider = :anthropic                      # LLM provider (only :anthropic for now)
  config.api_key = ENV['ANTHROPIC_API_KEY']         # Falls back to env var automatically
  config.model = 'claude-sonnet-4-20250514'                 # Default model
  config.database_path = '~/.ai_sentinel/db.sqlite3'  # SQLite database location
  config.max_context_messages = 50                  # Max conversation history per step
end
```

## Defining Workflows

Create a Ruby config file (e.g., `sentinel.rb`):

```ruby
require 'ai_sentinel'

AiSentinel.configure do |config|
  config.api_key = ENV['ANTHROPIC_API_KEY']
end

# Monitor prices every morning at 9 AM
AiSentinel.watch 'check_prices' do
  schedule '0 9 * * *'

  step :fetch, action: :http_get,
    url: 'https://api.example.com/prices'

  step :analyze, action: :ai_prompt,
    prompt: 'Analyze these prices for anomalies: {{fetch.body}}'

  step :notify, action: :http_post,
    url: 'https://hooks.slack.com/services/xxx',
    body: { text: '{{analyze.response}}' },
    condition: ->(ctx) { ctx[:analyze].response.include?('anomaly') }
end

# Check server health every 5 minutes
AiSentinel.watch 'health_check' do
  schedule '*/5 * * * *'

  step :check, action: :shell_command,
    command: 'curl -s -o /dev/null -w "%{http_code}" https://myapp.com/health'

  step :diagnose, action: :ai_prompt,
    system: 'You are a systems administrator. Be concise.',
    prompt: 'Server health check returned: {{check.stdout}}. Is this normal?',
    condition: ->(ctx) { ctx[:check].stdout.strip != '200' }
end

AiSentinel.start
```

## Actions

### `http_get`

```ruby
step :fetch, action: :http_get,
  url: 'https://api.example.com/data',
  headers: { 'Authorization' => 'Bearer {{token}}' }
```

Returns: `status`, `body`, `headers`

### `http_post`

```ruby
step :notify, action: :http_post,
  url: 'https://hooks.slack.com/services/xxx',
  body: { text: 'Alert: {{analyze.response}}' },
  headers: { 'Authorization' => 'Bearer token' }
```

Returns: `status`, `body`, `headers`

### `ai_prompt`

```ruby
step :analyze, action: :ai_prompt,
  prompt: 'Analyze this data: {{fetch.body}}',
  system: 'You are a data analyst.',    # optional system prompt
  model: 'claude-sonnet-4-20250514',            # optional, overrides default
  remember: true                        # persist conversation context (default: true)
```

Returns: `response`, `model`, `usage`

When `remember: true`, the conversation history is stored in SQLite and included in subsequent calls. This means the AI can reference previous analyses across scheduled runs.

### `shell_command`

```ruby
step :check, action: :shell_command,
  command: 'df -h / | tail -1',
  timeout: 30                           # seconds (default: 30)
```

Returns: `stdout`, `stderr`, `exit_code`, `success`

## Conditional Steps

Steps can have a `condition` lambda that receives the workflow context. The step is skipped if the condition returns `false`:

```ruby
step :alert, action: :http_post,
  url: 'https://hooks.slack.com/services/xxx',
  body: { text: 'Disk space critical!' },
  condition: ->(ctx) { ctx[:check].stdout.include?('9') }
```

## Template Interpolation

Use `{{step_name.field}}` to reference results from previous steps:

```ruby
step :summarize, action: :ai_prompt,
  prompt: 'Status: {{check.stdout}}, Exit: {{check.exit_code}}'
```

## CLI

```bash
# Start the scheduler with a config file
ai_sentinel start sentinel.rb

# Start in background mode
ai_sentinel start sentinel.rb -d

# List registered workflows
ai_sentinel list sentinel.rb

# Manually trigger a workflow
ai_sentinel run sentinel.rb check_prices

# View execution history
ai_sentinel history
ai_sentinel history check_prices -n 10

# View conversation context for a step
ai_sentinel context check_prices analyze

# Clear conversation context
ai_sentinel clear_context check_prices analyze

# Show version
ai_sentinel version
```

## Conversation Memory

AiSentinel persists AI conversation history in SQLite, keyed by `workflow_name:step_name`. This means:

- The AI agent accumulates context over time across scheduled runs
- It can reference previous analyses, spot trends, and provide richer insights
- Context is prunable via `max_context_messages` config or `clear_context` CLI command
- Set `remember: false` on a step to disable context for that step

## Development

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run linter
bundle exec rubocop

# Run both
bundle exec rake
```

## License

The gem is available as open source under the terms of the [MIT License](LICENSE).
