# frozen_string_literal: true

RSpec.describe AiSentinel::ContextCompactor, :db do
  let(:configuration) do
    config = AiSentinel::Configuration.new
    config.api_key = 'test-key'
    config.max_context_messages = 50
    config.compaction_threshold = 5
    config.compaction_buffer = 2
    config.logger = Logger.new(File::NULL)
    config
  end

  let(:context_key) { 'test_workflow:analyze' }

  let(:success_body) do
    {
      content: [{ type: 'text', text: 'Summary of previous conversations.' }],
      model: 'claude-sonnet-4-20250514',
      usage: {}
    }.to_json
  end

  before { AiSentinel.instance_variable_set(:@configuration, configuration) }

  def insert_messages(count)
    count.times do |i|
      AiSentinel::Persistence::Database.db[:conversation_messages].insert(
        context_key: context_key,
        user_message: "Question #{i}",
        assistant_message: "Answer #{i}",
        created_at: Time.now + i,
        updated_at: Time.now + i
      )
    end
  end

  describe '#compact_if_needed' do
    it 'does not compact when below threshold' do
      insert_messages(3)

      compactor = described_class.new(context_key: context_key, configuration: configuration)
      compactor.compact_if_needed

      count = AiSentinel::Persistence::Database.db[:conversation_messages]
                                               .where(context_key: context_key)
                                               .count
      expect(count).to eq(3)
    end

    it 'compacts when at or above threshold' do
      insert_messages(6)

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      compactor = described_class.new(context_key: context_key, configuration: configuration)
      compactor.compact_if_needed

      remaining = AiSentinel::Persistence::Database.db[:conversation_messages]
                                                   .where(context_key: context_key)
                                                   .count
      expect(remaining).to eq(configuration.compaction_buffer)
    end

    it 'creates a summary in the database' do
      insert_messages(6)

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      compactor = described_class.new(context_key: context_key, configuration: configuration)
      compactor.compact_if_needed

      summary = AiSentinel::Persistence::Database.db[:context_summaries]
                                                 .where(context_key: context_key)
                                                 .first

      expect(summary).not_to be_nil
      expect(summary[:summary]).to eq('Summary of previous conversations.')
      expect(summary[:messages_summarized_count]).to eq(4)
    end

    it 'preserves the most recent messages as the buffer' do
      insert_messages(6)

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      compactor = described_class.new(context_key: context_key, configuration: configuration)
      compactor.compact_if_needed

      remaining = AiSentinel::Persistence::Database.db[:conversation_messages]
                                                   .where(context_key: context_key)
                                                   .order(:created_at)
                                                   .all

      expect(remaining.map { |r| r[:user_message] }).to eq(['Question 4', 'Question 5'])
    end

    it 'includes existing summary in the summarization prompt' do
      AiSentinel::Persistence::Database.db[:context_summaries].insert(
        context_key: context_key,
        summary: 'Old summary of earlier conversations.',
        messages_summarized_count: 10,
        created_at: Time.now,
        updated_at: Time.now
      )

      insert_messages(6)

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .with(body: /Old summary of earlier conversations/)
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      compactor = described_class.new(context_key: context_key, configuration: configuration)
      compactor.compact_if_needed

      summary = AiSentinel::Persistence::Database.db[:context_summaries]
                                                 .where(context_key: context_key)
                                                 .first

      expect(summary[:messages_summarized_count]).to eq(14)
    end

    it 'sends remember: false for the summarization API call' do
      insert_messages(6)

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      compactor = described_class.new(context_key: context_key, configuration: configuration)
      compactor.compact_if_needed

      summary_messages = AiSentinel::Persistence::Database.db[:conversation_messages]
                                                          .where(context_key: ':')
                                                          .count
      expect(summary_messages).to eq(0)
    end
  end
end
