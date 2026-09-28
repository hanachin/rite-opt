# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/rite_opt/rite/reader"
require_relative "../lib/rite_opt/rite/parser"
require_relative "../lib/rite_opt/rite/opcodes"
require_relative "../lib/rite_opt/rite/instruction_decoder"
require_relative "../lib/rite_opt/rite/effect_analysis"
require_relative "../lib/rite_opt/rite/liveness"
require_relative "../lib/rite_opt/rite/cfg"
require_relative "../lib/rite_opt/rite/rewrite_error"
require_relative "../lib/rite_opt/rite/dead_store_elimination"

class DeadStoreEliminationTest < Minitest::Test
  def test_replaces_unused_load_with_nops_without_changing_size
    code = [opcode("LOADI_1"), 1, opcode("RETNIL")].pack("C*")
    input = rite(code:, nregs: 2)

    result = RiteOpt::Rite::DeadStoreElimination.call(input)

    assert_equal input.bytesize, result.bytesize
    assert_equal [0, 0, opcode("RETNIL")].pack("C*"), root_code(result)
  end

  def test_keeps_store_whose_value_is_returned
    code = [opcode("LOADI_1"), 1, opcode("RETURN"), 1].pack("C*")
    input = rite(code:, nregs: 2)

    result = RiteOpt::Rite::DeadStoreElimination.call(input)

    assert_equal code, root_code(result)
  end

  def test_removes_store_overwritten_before_use
    code = [
      opcode("LOADI_1"), 1,
      opcode("LOADI_2"), 1,
      opcode("RETURN"), 1
    ].pack("C*")
    input = rite(code:, nregs: 2)

    result = RiteOpt::Rite::DeadStoreElimination.call(input)

    assert_equal [0, 0, opcode("LOADI_2"), 1, opcode("RETURN"), 1].pack("C*"), root_code(result)
  end

  def test_removes_dead_move_chain
    code = [
      opcode("LOADI_1"), 1,
      opcode("MOVE"), 2, 1,
      opcode("RETNIL")
    ].pack("C*")
    input = rite(code:, nregs: 3)

    result = RiteOpt::Rite::DeadStoreElimination.call(input)

    assert_equal [0, 0, 0, 0, 0, opcode("RETNIL")].pack("C*"), root_code(result)
  end

  def test_keeps_store_used_on_one_branch
    # PCs: 0 LOADI_1 R1; 2 JMPIF R2,+2 -> 8; 6 RETNIL; 7 NOP; 8 RETURN R1
    code = [
      opcode("LOADI_1"), 1,
      opcode("JMPIF"), 2, 0, 2,
      opcode("RETNIL"),
      opcode("NOP"),
      opcode("RETURN"), 1
    ].pack("C*")
    input = rite(code:, nregs: 3)

    result = RiteOpt::Rite::DeadStoreElimination.call(input)

    assert_equal code, root_code(result)
  end

  def test_unknown_instruction_keeps_prior_register_values_live
    code = [
      opcode("LOADI_1"), 1,
      opcode("SEND"), 2, 0, 0,
      opcode("RETNIL")
    ].pack("C*")
    input = rite(code:, nregs: 3)

    result = RiteOpt::Rite::DeadStoreElimination.call(input)

    assert_equal code, root_code(result)
  end

  def test_removes_extension_with_dead_extended_instruction
    code = [
      opcode("EXT1"),
      opcode("LOADI_1"), 1, 1,
      opcode("RETNIL")
    ].pack("C*")
    input = rite(code:, nregs: 258)

    result = RiteOpt::Rite::DeadStoreElimination.call(input)

    assert_equal [0, 0, 0, 0, opcode("RETNIL")].pack("C*"), root_code(result)
  end

  def test_keeps_exit_values_when_nested_irep_may_capture_them
    child = irep_record(code: [opcode("RETNIL")].pack("C*"), nregs: 1)
    code = [opcode("LOADI_1"), 1, opcode("RETNIL")].pack("C*")
    input = rite(code:, nregs: 2, children: [child])

    result = RiteOpt::Rite::DeadStoreElimination.call(input)

    assert_equal code, root_code(result)
  end

  def test_is_idempotent
    input = rite(code: [opcode("LOADI_1"), 1, opcode("RETNIL")].pack("C*"), nregs: 2)

    first = RiteOpt::Rite::DeadStoreElimination.call(input)
    second = RiteOpt::Rite::DeadStoreElimination.call(first)

    assert_equal first, second
  end

  private

  def root_code(source)
    document = RiteOpt::Rite::Parser.parse(source)
    document.bytes(document.sections.first.root.iseq.code_span)
  end

  def rite(code:, nlocals: 1, nregs: 1, catches: [], children: [], extra_sections: [])
    irep = section("IREP", "0400" + irep_record(code:, nlocals:, nregs:, catches:, children:))
    footer = section("END\0".b, "")
    body = irep + extra_sections.join + footer
    "RITE0400" + [20 + body.bytesize].pack("N") + "MATZ0000" + body
  end

  def irep_record(code:, nlocals: 1, nregs: 1, catches: [], children: [])
    catch_bytes = catches.map { |row| row.pack("CNNN") }.join
    iseq = [catches.length].pack("n") + [code.bytesize].pack("N") + code + catch_bytes
    pool_and_symbols = [0, 0].pack("nn")
    record_size = 10 + iseq.bytesize + pool_and_symbols.bytesize
    record = [record_size, nlocals, nregs, children.length].pack("Nnnn") + iseq + pool_and_symbols
    record + children.join
  end

  def section(ident, payload)
    ident + [8 + payload.bytesize].pack("N") + payload
  end

  def opcode(name)
    RiteOpt::Rite::OPCODES.find { |candidate| candidate.name == name }.code
  end
end
