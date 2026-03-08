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
    ctx = AiSentinel::Persistence::Database.find_or_create_context(context_key)
    count.times do |i|
      AiSentinel::Persistence::Database.db[:conversation_messages].insert(
        conversation_context_id: ctx[:id],
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

      ctx = AiSentinel::Persistence::Database.db[:conversation_contexts].where(context_key: context_key).first
      count = AiSentinel::Persistence::Database.db[:conversation_messages]
                                               .where(conversation_context_id: ctx[:id])
                                               .count
      expect(count).to eq(3)
    end

    it 'compacts when at or above threshold' do
      insert_messages(6)

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      compactor = described_class.new(context_key: context_key, configuration: configuration)
      compactor.compact_if_needed

      ctx = AiSentinel::Persistence::Database.db[:conversation_contexts].where(context_key: context_key).first
      remaining = AiSentinel::Persistence::Database.db[:conversation_messages]
                                                   .where(conversation_context_id: ctx[:id])
                                                   .count
      expect(remaining).to eq(configuration.compaction_buffer)
    end

    it 'stores a summary on the conversation context' do
      insert_messages(6)

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      compactor = described_class.new(context_key: context_key, configuration: configuration)
      compactor.compact_if_needed

      ctx = AiSentinel::Persistence::Database.db[:conversation_contexts].where(context_key: context_key).first

      expect(ctx[:summary]).to eq('Summary of previous conversations.')
      expect(ctx[:messages_summarized_count]).to eq(4)
    end

    it 'preserves the most recent messages as the buffer' do
      insert_messages(6)

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      compactor = described_class.new(context_key: context_key, configuration: configuration)
      compactor.compact_if_needed

      ctx = AiSentinel::Persistence::Database.db[:conversation_contexts].where(context_key: context_key).first
      remaining = AiSentinel::Persistence::Database.db[:conversation_messages]
                                                   .where(conversation_context_id: ctx[:id])
                                                   .order(:created_at)
                                                   .all

      expect(remaining.map { |r| r[:user_message] }).to eq(['Question 4', 'Question 5'])
    end

    it 'includes existing summary in the summarization prompt' do
      ctx = AiSentinel::Persistence::Database.find_or_create_context(context_key)
      AiSentinel::Persistence::Database.db[:conversation_contexts]
                                       .where(id: ctx[:id])
                                       .update(summary: 'Old summary of earlier conversations.',
                                               messages_summarized_count: 10, updated_at: Time.now)

      insert_messages(6)

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .with(body: /Old summary of earlier conversations/)
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      compactor = described_class.new(context_key: context_key, configuration: configuration)
      compactor.compact_if_needed

      ctx = AiSentinel::Persistence::Database.db[:conversation_contexts].where(context_key: context_key).first

      expect(ctx[:messages_summarized_count]).to eq(14)
    end

    it 'sends remember: false for the summarization API call' do
      insert_messages(6)

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      compactor = described_class.new(context_key: context_key, configuration: configuration)
      compactor.compact_if_needed

      null_ctx = AiSentinel::Persistence::Database.db[:conversation_contexts]
                                                  .where(context_key: ':')
                                                  .first
      expect(null_ctx).to be_nil
    end
  end
end
