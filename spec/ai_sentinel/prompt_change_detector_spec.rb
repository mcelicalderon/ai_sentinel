# frozen_string_literal: true

RSpec.describe AiSentinel::PromptChangeDetector, :db do
  let(:context_key) { 'test_workflow:analyze' }

  describe '.compute_hash' do
    it 'returns a SHA256 hex digest' do
      hash = described_class.compute_hash('Analyze: {{fetch.body}}', 'You are an analyst.')
      expect(hash).to match(/\A[0-9a-f]{64}\z/)
    end

    it 'returns different hashes for different prompts' do
      hash1 = described_class.compute_hash('Prompt A')
      hash2 = described_class.compute_hash('Prompt B')
      expect(hash1).not_to eq(hash2)
    end

    it 'returns different hashes when system prompt changes' do
      hash1 = described_class.compute_hash('Same prompt', 'System A')
      hash2 = described_class.compute_hash('Same prompt', 'System B')
      expect(hash1).not_to eq(hash2)
    end

    it 'returns the same hash for identical inputs' do
      hash1 = described_class.compute_hash('Prompt', 'System')
      hash2 = described_class.compute_hash('Prompt', 'System')
      expect(hash1).to eq(hash2)
    end
  end

  describe '.save_hash' do
    it 'stores the prompt hash on the conversation context' do
      described_class.save_hash(context_key, 'abc123')

      ctx = AiSentinel::Persistence::Database.db[:conversation_contexts]
                                             .where(context_key: context_key)
                                             .first
      expect(ctx[:prompt_hash]).to eq('abc123')
    end

    it 'updates an existing prompt hash' do
      described_class.save_hash(context_key, 'abc123')
      described_class.save_hash(context_key, 'def456')

      ctx = AiSentinel::Persistence::Database.db[:conversation_contexts]
                                             .where(context_key: context_key)
                                             .first
      expect(ctx[:prompt_hash]).to eq('def456')
    end

    it 'does not create duplicate context records' do
      described_class.save_hash(context_key, 'abc123')
      described_class.save_hash(context_key, 'def456')

      count = AiSentinel::Persistence::Database.db[:conversation_contexts]
                                               .where(context_key: context_key)
                                               .count
      expect(count).to eq(1)
    end
  end

  describe '.detect_changes' do
    let(:step) do
      AiSentinel::Step.new(name: :analyze, action: :ai_prompt, prompt: 'New prompt', remember: true)
    end
    let(:workflow) do
      AiSentinel::Workflow.new(name: 'test_workflow', schedule_expression: '* * * * *', steps: [step])
    end
    let(:registry) { { 'test_workflow' => workflow } }

    it 'returns empty when no stored hashes exist' do
      changes = described_class.detect_changes(registry)
      expect(changes).to be_empty
    end

    it 'returns empty when context exists but has no prompt hash' do
      AiSentinel::Persistence::Database.find_or_create_context(context_key)

      changes = described_class.detect_changes(registry)
      expect(changes).to be_empty
    end

    it 'returns empty when prompt has not changed' do
      hash = described_class.compute_hash('New prompt')
      described_class.save_hash(context_key, hash)

      changes = described_class.detect_changes(registry)
      expect(changes).to be_empty
    end

    it 'returns a change when prompt differs from stored hash' do
      described_class.save_hash(context_key, 'old_hash_value')

      changes = described_class.detect_changes(registry)
      expect(changes.size).to eq(1)
      expect(changes.first.context_key).to eq(context_key)
      expect(changes.first.workflow_name).to eq('test_workflow')
      expect(changes.first.step_name).to eq('analyze')
    end

    it 'ignores steps that do not use remember' do
      no_remember_step = AiSentinel::Step.new(name: :analyze, action: :ai_prompt, prompt: 'New prompt',
                                              remember: false)
      wf = AiSentinel::Workflow.new(name: 'test_workflow', schedule_expression: '* * * * *',
                                    steps: [no_remember_step])
      reg = { 'test_workflow' => wf }

      described_class.save_hash(context_key, 'old_hash_value')

      changes = described_class.detect_changes(reg)
      expect(changes).to be_empty
    end

    it 'ignores non-ai_prompt steps' do
      http_step = AiSentinel::Step.new(name: :fetch, action: :http_get, url: 'https://example.com')
      wf = AiSentinel::Workflow.new(name: 'test_workflow', schedule_expression: '* * * * *', steps: [http_step])
      reg = { 'test_workflow' => wf }

      changes = described_class.detect_changes(reg)
      expect(changes).to be_empty
    end
  end

  describe '.clear_context_for' do
    it 'deletes conversation messages and resets summary' do
      ctx = AiSentinel::Persistence::Database.find_or_create_context(context_key)
      AiSentinel::Persistence::Database.db[:conversation_messages].insert(
        conversation_context_id: ctx[:id], user_message: 'q', assistant_message: 'a',
        created_at: Time.now, updated_at: Time.now
      )
      AiSentinel::Persistence::Database.db[:conversation_contexts]
                                       .where(id: ctx[:id])
                                       .update(summary: 'old summary', messages_summarized_count: 5)

      described_class.clear_context_for(context_key)

      msgs = AiSentinel::Persistence::Database.db[:conversation_messages]
                                              .where(conversation_context_id: ctx[:id]).count
      updated_ctx = AiSentinel::Persistence::Database.db[:conversation_contexts]
                                                     .where(id: ctx[:id]).first
      expect(msgs).to eq(0)
      expect(updated_ctx[:summary]).to be_nil
      expect(updated_ctx[:messages_summarized_count]).to eq(0)
    end
  end

  describe '.update_hash_for' do
    it 'saves the hash computed from the given templates' do
      described_class.update_hash_for(context_key, 'my prompt', 'my system')

      ctx = AiSentinel::Persistence::Database.db[:conversation_contexts]
                                             .where(context_key: context_key).first
      expect(ctx[:prompt_hash]).to eq(described_class.compute_hash('my prompt', 'my system'))
    end
  end
end
