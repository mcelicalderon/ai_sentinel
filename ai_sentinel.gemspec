# frozen_string_literal: true

require_relative 'lib/ai_sentinel/version'

Gem::Specification.new do |spec|
  spec.name = 'ai_sentinel'
  spec.version = AiSentinel::VERSION
  spec.authors = ['Mario Celi']
  spec.email = ['mcelicalderon@gmail.com']

  spec.summary = 'Lightweight AI task scheduler with conditional actions'
  spec.description = 'Schedule AI-driven tasks to run at specified times, process results through LLMs, ' \
                     'and take conditional actions based on the output. Designed to be lightweight and self-hostable.'
  spec.homepage = 'https://github.com/mcelicalderon/ai_sentinel'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?('spec/', 'test/', '.git', '.github', 'bin/')
    end
  end

  spec.bindir = 'exe'
  spec.executables = ['ai_sentinel']
  spec.require_paths = ['lib']

  spec.add_dependency 'dotenv', '~> 3.0'
  spec.add_dependency 'faraday', '~> 2.0'
  spec.add_dependency 'rufus-scheduler', '~> 3.9'
  spec.add_dependency 'sequel', '~> 5.0'
  spec.add_dependency 'sqlite3', '~> 2.0'
  spec.add_dependency 'thor', '~> 1.0'
end
