# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/rite_opt/rite/reader"
require_relative "../lib/rite_opt/rite/parser"
require_relative "../lib/rite_opt/rite/opcodes"
require_relative "../lib/rite_opt/rite/instruction_decoder"
require_relative "../lib/rite_opt/rite/effect_analysis"
require_relative "../lib/rite_opt/rite/cfg"
require_relative "../lib/rite_opt/rite/rewrite_error"
require_relative "../lib/rite_opt/rite/copy_propagation"

class CopyPropagationTest < Minitest::Test
  def test_propagates_move_source_to_later_use
    code = [
      opcode("MOVE"), 2, 1,
      opcode("RETURN"), 2
    ].pack("C*")

    result = RiteOpt::Rite::CopyPropagation.call(rite(code:, nregs: 3))

    assert_equal [
      opcode("MOVE"), 2, 1,
      opcode("RETURN"), 1
    ].pack("C*"), root_code(result)
  end

  def test_collapses_transitive_copy_chain
    code = [
      opcode("MOVE"), 2, 1,
      opcode("MOVE"), 3, 2,
      opcode("RETURN"), 3
    ].pack("C*")

    result = RiteOpt::Rite::CopyPropagation.call(rite(code:, nregs: 4))

    assert_equal [
      opcode("MOVE"), 2, 1,
      opcode("MOVE"), 3, 1,
      opcode("RETURN"), 1
    ].pack("C*"), root_code(result)
  end

  def test_propagates_into_conditional_jump_in_same_block
    code = [
      opcode("MOVE"), 2, 1,
      opcode("JMPIF"), 2, 0, 0,
      opcode("RETNIL")
    ].pack("C*")

    result = RiteOpt::Rite::CopyPropagation.call(rite(code:, nregs: 3))

    assert_equal [
      opcode("MOVE"), 2, 1,
      opcode("JMPIF"), 1, 0, 0,
      opcode("RETNIL")
    ].pack("C*"), root_code(result)
  end

  def test_kills_copy_when_source_is_redefined
    code = [
      opcode("MOVE"), 2, 1,
      opcode("LOADI_1"), 1,
      opcode("RETURN"), 2
    ].pack("C*")

    result = RiteOpt::Rite::CopyPropagation.call(rite(code:, nregs: 3))

    assert_equal code, root_code(result)
  end

  def test_kills_copy_when_destination_is_redefined
    code = [
      opcode("MOVE"), 2, 1,
      opcode("LOADI_1"), 2,
      opcode("RETURN"), 2
    ].pack("C*")

    result = RiteOpt::Rite::CopyPropagation.call(rite(code:, nregs: 3))

    assert_equal code, root_code(result)
  end

  def test_does_not_propagate_across_basic_block_boundary
    # PCs: 0 MOVE R2,R1; 3 JMP +0 -> 6; 6 RETURN R2
    code = [
      opcode("MOVE"), 2, 1,
      opcode("JMP"), 0, 0,
      opcode("RETURN"), 2
    ].pack("C*")

    result = RiteOpt::Rite::CopyPropagation.call(rite(code:, nregs: 3))

    assert_equal code, root_code(result)
  end

  def test_unmodelled_instruction_is_copy_barrier
    code = [
      opcode("MOVE"), 2, 1,
      opcode("SEND"), 0, 0, 0,
      opcode("RETURN"), 2
    ].pack("C*")

    result = RiteOpt::Rite::CopyPropagation.call(rite(code:, nregs: 3))

    assert_equal code, root_code(result)
  end

  def test_skips_rewrite_that_would_change_ext_width
    code = [
      opcode("EXT2"), opcode("MOVE"), 2, 1, 1,
      opcode("RETURN"), 2
    ].pack("C*")

    input = rite(code:, nregs: 258)
    result = RiteOpt::Rite::CopyPropagation.call(input)

    assert_equal input.bytesize, result.bytesize
    assert_equal code, root_code(result)
  end

  def test_rewrites_nested_irep
    child_code = [
      opcode("MOVE"), 2, 1,
      opcode("RETURN"), 2
    ].pack("C*")
    child = irep_record(code: child_code, nregs: 3)
    input = rite(code: [opcode("RETNIL")].pack("C*"), children: [child])

    result = RiteOpt::Rite::CopyPropagation.call(input)
    document = RiteOpt::Rite::Parser.parse(result)
    child_irep = document.sections.first.root.children.fetch(0)

    assert_equal [
      opcode("MOVE"), 2, 1,
      opcode("RETURN"), 1
    ].pack("C*"), document.bytes(child_irep.iseq.code_span)
  end

  def test_is_idempotent
    input = rite(
      code: [opcode("MOVE"), 2, 1, opcode("RETURN"), 2].pack("C*"),
      nregs: 3
    )

    first = RiteOpt::Rite::CopyPropagation.call(input)
    second = RiteOpt::Rite::CopyPropagation.call(first)

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
