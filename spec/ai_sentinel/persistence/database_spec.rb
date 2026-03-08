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

    it 'creates conversation_messages table' do
      expect(described_class.db.table_exists?(:conversation_messages)).to be true
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
