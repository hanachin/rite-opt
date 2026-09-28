# frozen_string_literal: true

require "optparse"
require_relative "../rite_opt"

module RiteOpt
  class CLI
    PASSES = [
      [:debug_removal, Rite::DebugRemoval],
      [:lvar_removal, Rite::LvarRemoval],
      [:unreachable_code_elimination, Rite::UnreachableCodeElimination],
      [:nop_removal, Rite::NopRemoval]
    ].freeze

    def self.run(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr)
      new(argv, stdin:, stdout:, stderr:).run
    end

    def initialize(argv, stdin:, stdout:, stderr:)
      @argv = argv.dup
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
    end

    def run
      options = default_options
      parser = option_parser(options)
      parser.parse!(@argv)

      return print_help(parser) if options[:help]
      return print_version if options[:version]

      input_path = input_path(parser)
      source = read_input(input_path)
      result = optimize(source, options)
      write_output(result, options[:output])
      0
    rescue OptionParser::ParseError => error
      @stderr.puts error.message
      @stderr.puts parser
      2
    rescue Rite::ReadError, Rite::ParseError, Rite::InstructionDecodeError, Rite::UnsupportedRewrite, SystemCallError => error
      @stderr.puts error.message
      1
    end

    private

    def default_options
      {
        debug_removal: true,
        lvar_removal: true,
        unreachable_code_elimination: true,
        nop_removal: true,
        output: nil,
        help: false,
        version: false
      }
    end

    def option_parser(options)
      OptionParser.new do |parser|
        parser.banner = "Usage: rite-opt [options] INPUT"

        parser.on("-o", "--output FILE", "Write output to FILE instead of stdout") do |path|
          options[:output] = path
        end
        parser.on("--no-debug-removal", "Disable DBG section removal") do
          options[:debug_removal] = false
        end
        parser.on("--no-lvar-removal", "Disable LVAR section removal") do
          options[:lvar_removal] = false
        end
        parser.on("--no-unreachable-code-elimination", "Disable unreachable code elimination") do
          options[:unreachable_code_elimination] = false
        end
        parser.on("--no-nop-removal", "Disable NOP removal") do
          options[:nop_removal] = false
        end
        parser.on("-v", "--version", "Print version") do
          options[:version] = true
        end
        parser.on("-h", "--help", "Print help") do
          options[:help] = true
        end
      end
    end

    def input_path(parser)
      raise OptionParser::MissingArgument, "INPUT" if @argv.empty?
      raise OptionParser::InvalidArgument, "expected one INPUT" unless @argv.one?

      @argv.first
    end

    def read_input(path)
      return read_stream(@stdin) if path == "-"

      File.binread(path)
    end

    def read_stream(stream)
      stream.binmode if stream.respond_to?(:binmode)
      stream.read.b
    end

    def optimize(source, options)
      PASSES.reduce(source) do |bytes, (name, pass)|
        options.fetch(name) ? pass.call(bytes) : bytes
      end
    end

    def write_output(bytes, path)
      if path && path != "-"
        File.binwrite(path, bytes)
      else
        @stdout.binmode if @stdout.respond_to?(:binmode)
        @stdout.write(bytes)
      end
    end

    def print_help(parser)
      @stdout.puts parser
      0
    end

    def print_version
      @stdout.puts VERSION
      0
    end
  end
end
