# frozen_string_literal: true

require 'pronto'
require 'shellwords'

module Pronto
  class ESLintNpm < Runner
    CONFIG_FILE = '.pronto_eslint_npm.yml'.freeze
    CONFIG_KEYS = %w[eslint_executable files_to_lint cmd_line_opts multi_project_folders].freeze
    SEVERITY_LEVELS = [nil, :warning, :error].freeze

    attr_writer :eslint_executable, :cmd_line_opts, :multi_project_folders

    def eslint_executable
      @eslint_executable || 'eslint'
    end

    def files_to_lint
      @files_to_lint || /(\.js|\.es6)$/
    end

    def cmd_line_opts
      @cmd_line_opts || ''
    end

    def files_to_lint=(regexp)
      @files_to_lint = regexp.is_a?(Regexp) && regexp || Regexp.new(regexp)
    end

    def multi_project_folders
      @multi_project_folders || []
    end

    def config_options
      @config_options ||=
        begin
          config_file = File.join(repo_path, CONFIG_FILE)
          File.exist?(config_file) && YAML.load_file(config_file) || {}
        end
    end

    def read_config
      config_options.each do |key, val|
        next unless CONFIG_KEYS.include?(key.to_s)
        send("#{key}=", val)
      end
    end

    def run
      return [] if !@patches || @patches.count.zero?

      read_config

      @patches
        .select { |patch| patch.additions > 0 }
        .select { |patch| js_file?(patch.new_file_full_path) }
        .map { |patch| inspect(patch) }
        .flatten.compact
    end

    private

    def repo_path
      @repo_path ||= @patches.first.repo.path
    end

    def inspect(patch)
      lines = patch.added_lines
      offences = run_eslint(patch)
      clean_up_eslint_output(offences)
        .map do |offence|
          range = offence['line']..(offence['endLine'] || offence['line'])
          line = lines.select { |line| range.cover?(line.new_lineno) }.last
          new_message(offence, line) if line
        end
    end

    def new_message(offence, line)
      path  = line.patch.delta.new_file[:path]
      level = SEVERITY_LEVELS.fetch(offence['severity'], :warning)

      Message.new(path, line, level, offence['message'], nil, self.class)
    end

    def js_file?(path)
      files_to_lint =~ path.to_s
    end

    def run_eslint(patch)
      Dir.chdir(repo_path) do
        JSON.parse `#{eslint_command_line(patch.new_file_full_path.to_s)}`
      end
    end

    def eslint_command_line(path)
      relative_path = path.gsub(repo_path.to_s, '')
      multi_project_folders.each do |project_path|
        if relative_path.start_with?("/#{project_path}")
          return "cd #{project_path} && #{eslint_executable} #{cmd_line_opts} #{Shellwords.escape(path)} -f json"
        end
      end
      "#{eslint_executable} #{cmd_line_opts} #{Shellwords.escape(path)} -f json"
    end

    def clean_up_eslint_output(output)
      # 1. Filter out offences without a warning or error
      # 2. Get the messages for that file
      # 3. Ignore errors without a line number for now
      output
        .select { |offence| offence['errorCount'] + offence['warningCount'] > 0 }
        .map { |offence| offence['messages'] }
        .flatten.select { |offence| offence['line'] }
    end
  end
end
