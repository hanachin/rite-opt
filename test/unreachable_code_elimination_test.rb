# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/rite_opt/rite/reader"
require_relative "../lib/rite_opt/rite/parser"
require_relative "../lib/rite_opt/rite/opcodes"
require_relative "../lib/rite_opt/rite/instruction_decoder"
require_relative "../lib/rite_opt/rite/cfg"
require_relative "../lib/rite_opt/rite/rewrite_error"
require_relative "../lib/rite_opt/rite/unreachable_code_elimination"

class UnreachableCodeEliminationTest < Minitest::Test
  def test_replaces_unreachable_block_with_nops_without_changing_size
    # PCs: 0 RETURN R1; 2 LOADI_1 R1; 4 RETURN R1
    code = [
      opcode("RETURN"), 1,
      opcode("LOADI_1"), 1,
      opcode("RETURN"), 1
    ].pack("C*")
    input = rite(code:)

    result = RiteOpt::Rite::UnreachableCodeElimination.call(input)
    rewritten_code = root_code(result)

    assert_equal input.bytesize, result.bytesize
    assert_equal [opcode("RETURN"), 1, 0, 0, 0, 0].pack("C*"), rewritten_code
  end

  def test_keeps_branch_targets_reachable
    # PCs: 0 JMP +2 -> 5; 3 NOP; 4 NOP; 5 STOP
    code = [opcode("JMP"), 0, 2, opcode("NOP"), opcode("NOP"), opcode("STOP")].pack("C*")
    input = rite(code:)

    result = RiteOpt::Rite::UnreachableCodeElimination.call(input)

    assert_equal [opcode("JMP"), 0, 2, 0, 0, opcode("STOP")].pack("C*"), root_code(result)
  end

  def test_keeps_reachable_catch_target
    # PCs: 0 NOP; 1 RETURN R1; 3 STOP
    code = [opcode("NOP"), opcode("RETURN"), 1, opcode("STOP")].pack("C*")
    input = rite(code:, catches: [[1, 0, 3, 3]])

    result = RiteOpt::Rite::UnreachableCodeElimination.call(input)

    assert_equal code, root_code(result)
  end

  def test_preserves_debug_section_because_pcs_do_not_move
    input = rite(
      code: [opcode("RETURN"), 1, opcode("STOP")].pack("C*"),
      extra_sections: [section("DBG\0".b, "debug-data")]
    )

    result = RiteOpt::Rite::UnreachableCodeElimination.call(input)
    document = RiteOpt::Rite::Parser.parse(result)

    assert_equal input.bytesize, result.bytesize
    assert document.sections.any? { |section| section in RiteOpt::Rite::DebugSection }
  end

  def test_is_idempotent
    input = rite(code: [opcode("RETURN"), 1, opcode("STOP")].pack("C*"))

    first = RiteOpt::Rite::UnreachableCodeElimination.call(input)
    second = RiteOpt::Rite::UnreachableCodeElimination.call(first)

    assert_equal first, second
  end

  private

  def root_code(source)
    document = RiteOpt::Rite::Parser.parse(source)
    document.bytes(document.sections.first.root.iseq.code_span)
  end

  def rite(code:, catches: [], children: [], extra_sections: [])
    irep = section("IREP", "0400" + irep_record(code:, catches:, children:))
    footer = section("END\0".b, "")
    body = irep + extra_sections.join + footer
    "RITE0400" + [20 + body.bytesize].pack("N") + "MATZ0000" + body
  end

  def irep_record(code:, catches: [], children: [])
    catch_bytes = catches.map { |row| row.pack("CNNN") }.join
    iseq = [catches.length].pack("n") + [code.bytesize].pack("N") + code + catch_bytes
    pool_and_symbols = [0, 0].pack("nn")
    record_size = 10 + iseq.bytesize + pool_and_symbols.bytesize
    record = [record_size, 1, 1, children.length].pack("Nnnn") + iseq + pool_and_symbols
    record + children.join
  end

  def section(ident, payload)
    ident + [8 + payload.bytesize].pack("N") + payload
  end

  def opcode(name)
    RiteOpt::Rite::OPCODES.find { |opcode| opcode.name == name }.code
  end
end
