# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  enable_coverage :branch
end

require 'tmpdir'
require 'ai_sentinel'
require 'webmock/rspec'

WebMock.disable_net_connect!

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.before do
    AiSentinel.reset!
  end

  config.around do |example|
    if example.metadata[:db]
      db_path = File.join(Dir.tmpdir, "ai_sentinel_test_#{Process.pid}_#{rand(10_000)}.sqlite3")
      AiSentinel::Persistence::Database.setup(db_path)
      example.run
      AiSentinel::Persistence::Database.disconnect
      FileUtils.rm_f(db_path)
    else
      example.run
    end
  end
end
