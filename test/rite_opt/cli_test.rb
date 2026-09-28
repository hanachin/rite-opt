# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require "tmpdir"
require_relative "../../lib/rite_opt/cli"

class RiteOptCliTest < Minitest::Test
  def test_runs_default_pipeline_to_stdout
    input = rite(
      code: [opcode("LOADI_1"), 1, opcode("RETNIL")].pack("C*"),
      nregs: 2,
      extra_sections: [
        section("DBG\0".b, "debug-data"),
        section("LVAR".b, "lvar-data")
      ]
    )
    stdout = StringIO.new(+"".b)
    stderr = StringIO.new

    status = RiteOpt::CLI.run(["-"], stdin: StringIO.new(input), stdout:, stderr:)

    assert_equal 0, status
    assert_empty stderr.string

    document = RiteOpt::Rite::Parser.parse(stdout.string)
    assert_equal [RiteOpt::Rite::IrepSection], document.sections.map(&:class)
    assert_equal [opcode("RETNIL")].pack("C*"), document.bytes(document.sections.first.root.iseq.code_span)
  end

  def test_disables_selected_passes
    debug = section("DBG\0".b, "debug-data")
    lvar = section("LVAR".b, "lvar-data")
    input = rite(code: [0, 118].pack("C*"), extra_sections: [debug, lvar])
    stdout = StringIO.new(+"".b)

    status = RiteOpt::CLI.run(
      ["--no-debug-removal", "--no-nop-removal", "-"],
      stdin: StringIO.new(input),
      stdout:,
      stderr: StringIO.new
    )

    assert_equal 0, status
    document = RiteOpt::Rite::Parser.parse(stdout.string)
    assert_equal [RiteOpt::Rite::IrepSection, RiteOpt::Rite::DebugSection], document.sections.map(&:class)
    assert_equal [0, 118].pack("C*"), document.bytes(document.sections.first.root.iseq.code_span)
  end

  def test_disables_dead_store_elimination
    code = [opcode("LOADI_1"), 1, opcode("RETNIL")].pack("C*")
    input = rite(code:, nregs: 2)
    stdout = StringIO.new(+"".b)

    status = RiteOpt::CLI.run(
      ["--no-dead-store-elimination", "--no-nop-removal", "-"],
      stdin: StringIO.new(input),
      stdout:,
      stderr: StringIO.new
    )

    assert_equal 0, status
    document = RiteOpt::Rite::Parser.parse(stdout.string)
    assert_equal code, document.bytes(document.sections.first.root.iseq.code_span)
  end

  def test_writes_output_file
    Dir.mktmpdir do |dir|
      input_path = File.join(dir, "input.mrb")
      output_path = File.join(dir, "output.mrb")
      File.binwrite(input_path, rite(code: [0, 118].pack("C*")))
      stdout = StringIO.new(+"".b)

      status = RiteOpt::CLI.run(
        ["-o", output_path, input_path],
        stdin: StringIO.new,
        stdout:,
        stderr: StringIO.new
      )

      assert_equal 0, status
      assert_empty stdout.string
      document = RiteOpt::Rite::Parser.parse(File.binread(output_path))
      assert_equal [118].pack("C*"), document.bytes(document.sections.first.root.iseq.code_span)
    end
  end

  def test_prints_version_without_input
    stdout = StringIO.new

    status = RiteOpt::CLI.run(["--version"], stdout:, stdin: StringIO.new, stderr: StringIO.new)

    assert_equal 0, status
    assert_equal "#{RiteOpt::VERSION}\n", stdout.string
  end

  private

  def rite(code:, nregs: 1, extra_sections: [])
    irep = section("IREP", "0400" + irep_record(code:, nregs:))
    footer = section("END\0".b, "")
    body = irep + extra_sections.join + footer
    "RITE0400" + [20 + body.bytesize].pack("N") + "MATZ0000" + body
  end

  def irep_record(code:, nregs:)
    iseq = [0].pack("n") + [code.bytesize].pack("N") + code
    pool_and_symbols = [0, 0].pack("nn")
    record_size = 10 + iseq.bytesize + pool_and_symbols.bytesize
    [record_size, 1, nregs, 0].pack("Nnnn") + iseq + pool_and_symbols
  end

  def section(ident, payload)
    ident + [8 + payload.bytesize].pack("N") + payload
  end

  def opcode(name)
    RiteOpt::Rite::OPCODES.find { |candidate| candidate.name == name }.code
  end
end
