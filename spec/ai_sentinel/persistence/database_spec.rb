# frozen_string_literal: true

RSpec.describe AiSentinel::Persistence::Database, :db do
  describe '.setup' do
    it 'creates a database connection' do
      expect(described_class).to be_connected
      expect(described_class.db).not_to be_nil
    end

    it 'creates execution_logs table' do
      expect(described_class.db.table_exists?(:execution_logs)).to be true
    end

    it 'creates step_results table' do
      expect(described_class.db.table_exists?(:step_results)).to be true
    end

    it 'creates conversation_contexts table' do
      expect(described_class.db.table_exists?(:conversation_contexts)).to be true
    end

    it 'creates conversation_messages table' do
      expect(described_class.db.table_exists?(:conversation_messages)).to be true
    end
  end

  describe '.find_or_create_context' do
    it 'creates a new context record when none exists' do
      ctx = described_class.find_or_create_context('wf:step')

      expect(ctx[:context_key]).to eq('wf:step')
      expect(ctx[:prompt_hash]).to be_nil
      expect(ctx[:summary]).to be_nil
      expect(ctx[:messages_summarized_count]).to eq(0)
    end

    it 'returns the existing context record' do
      first = described_class.find_or_create_context('wf:step')
      second = described_class.find_or_create_context('wf:step')

      expect(first[:id]).to eq(second[:id])
    end
  end

  describe '.disconnect' do
    it 'disconnects and clears the database' do
      described_class.disconnect

      expect(described_class).not_to be_connected

      db_path = File.join(Dir.tmpdir, 'ai_sentinel_reconnect_test.sqlite3')
      described_class.setup(db_path)
      FileUtils.rm_f(db_path)
    end
  end
end
