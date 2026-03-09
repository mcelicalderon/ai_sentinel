# frozen_string_literal: true

RSpec.describe AiSentinel::Scheduler, :db do
  let(:configuration) do
    config = AiSentinel::Configuration.new
    config.api_key = 'test-key'
    config.logger = Logger.new(File::NULL)
    config
  end

  before { AiSentinel.instance_variable_set(:@configuration, configuration) }

  describe '#trigger' do
    it 'manually runs a workflow' do
      stub_request(:get, 'https://api.example.com/data')
        .to_return(status: 200, body: 'ok')

      workflow = AiSentinel::Workflow.new(
        name: 'test',
        schedule_expression: '0 9 * * *',
        steps: [
          AiSentinel::Step.new(name: :fetch, action: :http_get, url: 'https://api.example.com/data')
        ]
      )

      registry = { 'test' => workflow }
      scheduler = described_class.new(registry, configuration)
      context = scheduler.trigger('test')

      expect(context[:fetch].status).to eq(200)
    end

    it 'raises for unknown workflow' do
      scheduler = described_class.new({}, configuration)

      expect { scheduler.trigger('nonexistent') }.to raise_error(AiSentinel::Error, /Unknown workflow/)
    end
  end

  describe '#start' do
    let(:workflow) do
      AiSentinel::Workflow.new(
        name: 'test',
        schedule_expression: '0 9 * * *',
        steps: [
          AiSentinel::Step.new(name: :fetch, action: :http_get, url: 'https://api.example.com/data')
        ]
      )
    end
    let(:registry) { { 'test' => workflow } }
    let(:scheduler) { described_class.new(registry, configuration) }
    let(:mock_rufus) { instance_double(Rufus::Scheduler, cron: nil, shutdown: nil) }

    before do
      allow(Rufus::Scheduler).to receive(:new).and_return(mock_rufus)
      allow(mock_rufus).to receive(:join) { scheduler.stop }
    end

    it 'registers workflows and joins the scheduler' do
      scheduler.start

      expect(mock_rufus).to have_received(:join)
    end

    it 'traps INT and TERM signals' do
      allow(scheduler).to receive(:trap)

      scheduler.start

      expect(scheduler).to have_received(:trap).with('INT')
      expect(scheduler).to have_received(:trap).with('TERM')
    end

    it 'cleans up PID file on stop' do
      Dir.mktmpdir do |tmpdir|
        pid_path = File.join(tmpdir, 'ai_sentinel.pid')
        configuration.pid_file = pid_path
        File.write(pid_path, '12345')

        scheduler.start

        expect(File.exist?(pid_path)).to be false
      end
    end

    context 'when working_directory is set' do
      before do
        allow(FileUtils).to receive(:mkdir_p)
        allow(Dir).to receive(:chdir)
      end

      it 'changes to the configured directory' do
        configuration.working_directory = '/opt/etc/ai_sentinel'

        scheduler.start

        expect(Dir).to have_received(:chdir).with('/opt/etc/ai_sentinel')
      end
    end

    context 'when working_directory is nil' do
      it 'does not change directory' do
        allow(Dir).to receive(:chdir)

        scheduler.start

        expect(Dir).not_to have_received(:chdir)
      end
    end

    context 'when daemonize is true' do
      before do
        allow(Process).to receive(:daemon)
        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:write)
      end

      it 'calls Process.daemon before creating the scheduler' do
        call_order = []
        allow(Process).to receive(:daemon) { call_order << :daemon }
        allow(Rufus::Scheduler).to receive(:new) {
          call_order << :scheduler
          mock_rufus
        }

        scheduler.start(daemonize: true)

        expect(call_order).to eq(%i[daemon scheduler])
      end

      it 'writes a PID file' do
        scheduler.start(daemonize: true)

        expect(File).to have_received(:write).with(scheduler.pid_file, Process.pid.to_s)
      end
    end
  end
end
