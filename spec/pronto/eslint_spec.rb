# frozen_string_literal: true

require 'spec_helper'

module Pronto
  describe ESLintNpm do
    let(:eslint) { ESLintNpm.new(patches) }
    let(:patches) { [] }

    describe '#run' do
      subject(:run) { eslint.run }

      context 'patches are nil' do
        let(:patches) { nil }

        it 'returns an empty array' do
          expect(run).to eql([])
        end
      end

      context 'no patches' do
        let(:patches) { [] }

        it 'returns an empty array' do
          expect(run).to eql([])
        end
      end

      context 'patches with a one error and a four warnings' do
        include_context 'test repo'

        let(:patches) { repo.diff('master') }

        it 'returns correct number of errors' do
          expect(run.count).to eql(7)
        end

        it 'has correct messages' do
          expect(run.map(&:msg)).to eql([
            "'foo' is not defined.",
            "'foo' is not defined.",
            "More than 2 blank lines not allowed.",
            "'Empty' is defined but never used.",
            "'HelloWorld' is defined but never used.",
            "'foo' is not defined.",
            "'foo' is not defined."
          ])
        end

        it 'has correct line numbers' do
          expect(run.map { |m| m.line.new_lineno }).to eql([3, 3, 9, 9, 1, 3, 3])
        end

        it 'has correct levels' do
          expect(run.map(&:level)).to eql([
            :error, :error, :warning, :error, :error, :error, :error
          ])
        end

        context(
          'with files to lint config that never matches',
          config: { 'files_to_lint' => 'will never match' }
        ) do
          it 'returns zero errors' do
            expect(run.count).to eql(0)
          end
        end

        context(
          'with files to lint config that matches only .js',
          config: { 'files_to_lint' => '\.js$' }
        ) do
          it 'returns correct amount of errors' do
            expect(run.count).to eql(4)
          end

          it 'has correct messages' do
            expect(run.map(&:msg)).to eql([
              "'foo' is not defined.",
              "'foo' is not defined.",
              "More than 2 blank lines not allowed.",
              "'Empty' is defined but never used."
            ])
          end
        end

        context(
          'with cmd_line_opts to include .html',
          config: { 'cmd_line_opts' => '--ext .html' }
        ) do
          it 'returns correct number of errors' do
            expect(run.count).to eql(7)
          end

          it 'has correct messages' do
            expect(run.map(&:msg)).to eql([
              "'foo' is not defined.",
              "'foo' is not defined.",
              "More than 2 blank lines not allowed.",
              "'Empty' is defined but never used.",
              "'HelloWorld' is defined but never used.",
              "'foo' is not defined.",
              "'foo' is not defined."
            ])
          end
        end

        context(
          'with different eslint executable',
          config: { 'eslint_executable' => './custom_eslint.sh' }
        ) do
          it 'calls the custom eslint eslint_executable' do
            expect { run }.to raise_error(JSON::ParserError, /custom eslint called/)
          end
        end
      end

      context 'repo with ignored and not ignored file, each with three warnings' do
        include_context 'eslintignore repo'

        let(:patches) { repo.diff('master') }

        it 'returns correct number of errors' do
          expect(run.count).to eql(3)
        end

        it 'has correct first message' do
          expect(run.first.msg).to eql("'HelloWorld' is defined but never used.")
        end
      end
    end

    describe '#files_to_lint' do
      subject(:files_to_lint) { eslint.files_to_lint }

      it 'matches .js by default' do
        expect(files_to_lint).to match('my_js.js')
      end

      it 'matches .es6 by default' do
        expect(files_to_lint).to match('my_js.es6')
      end
    end

    describe '#eslint_executable' do
      subject(:eslint_executable) { eslint.eslint_executable }

      it 'is `eslint` by default' do
        expect(eslint_executable).to eql('eslint')
      end

      context(
        'with different eslint executable config',
        config: { 'eslint_executable' => 'custom_eslint' }
      ) do
        it 'is correct' do
          eslint.read_config
          expect(eslint_executable).to eql('custom_eslint')
        end
      end
    end

    describe '#eslint_command_line' do
      include_context 'eslintignore repo'
      subject(:eslint_command_line) { eslint.send(:eslint_command_line, path) }
      let(:path) { '/some/path.rb' }
      let(:patches) { repo.diff('master') }

      it 'adds json output flag' do
        expect(eslint_command_line).to include('-f json')
      end

      it 'adds path' do
        expect(eslint_command_line).to include(path)
      end

      it 'starts with eslint executable' do
        expect(eslint_command_line).to start_with(eslint.eslint_executable)
      end

      context 'with path that should be escaped' do
        let(:path) { '/must be/$escaped' }

        it 'escapes the path correctly' do
          expect(eslint_command_line).to include('/must\\ be/\\$escaped')
        end

        it 'does not include unescaped path' do
          expect(eslint_command_line).not_to include(path)
        end
      end

      context(
        'with some command line options',
        config: { 'cmd_line_opts' => '--my command --line opts' }
      ) do
        it 'includes the custom command line options' do
          eslint.read_config
          expect(eslint_command_line).to include('--my command --line opts')
        end
      end

      context(
        'with files to lint config that matches the project folder',
        config: { 'multi_project_folders' => {'project1' => {}} }
      ) do
        let(:path) { '/project1/hello.js' }

        it 'enters the project folder to run eslint' do
          eslint.read_config
          expect(eslint_command_line).to include('cd project1')
        end
      end

      context(
        'with files to lint config that doesnt match any project',
        config: { 'multi_project_folders' => {'project1' => {}} }
      ) do
        let(:path) { '/project2/hello.js' }

        it 'does not enter any project folder' do
          eslint.read_config
          expect(eslint_command_line).not_to include('cd project2')
          expect(eslint_command_line).not_to include('cd project1')
        end
      end
    end

    describe '#multi_project_folders' do
      include_context 'eslintignore repo'
      let(:patches) { repo.diff('master') }
      subject(:eslint_command_line) { eslint.send(:eslint_command_line, path) }
      context(
        'with config to load different projects',
        config: { 'multi_project_folders' => {'p1' => {}, 'p2' => {}} }
      ) do
        it 'adds project1 and project2' do
          eslint.read_config
          expect(eslint.multi_project_folders).to include('p1')
          expect(eslint.multi_project_folders).to include('p2')
        end
      end

      context(
        'with config to load command line options from project configuration',
        config: { 'multi_project_folders' => {'p1' => {'cmd_line_opts' => '--extra'}} }
      ) do
        let(:path) { '/p1/path.rb' }

        it 'uses command line from project configuration' do
          eslint.read_config
          expect(eslint.multi_project_folders).to include('p1')
          expect(eslint_command_line).to include('--extra')
        end
      end

      context(
        'with config to load project configuration but uses default command line options',
        config: { 'multi_project_folders' => {'p1' => {}}, 'cmd_line_opts' => '--default' }
      ) do
        let(:path) { '/project1/path.rb' }

        it 'uses command line from project configuration' do
          eslint.read_config
          expect(eslint.multi_project_folders).to include('p1')
          expect(eslint_command_line).to include('--default')
        end
      end
    end
  end
end
