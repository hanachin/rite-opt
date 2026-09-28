# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/rite_opt/rite/reader"
require_relative "../lib/rite_opt/rite/parser"
require_relative "../lib/rite_opt/rite/opcodes"
require_relative "../lib/rite_opt/rite/instruction_decoder"
require_relative "../lib/rite_opt/rite/rewrite_error"
require_relative "../lib/rite_opt/rite/irep_builder"
require_relative "../lib/rite_opt/rite/nop_removal"

class NopRemovalTest < Minitest::Test
  def test_removes_nops_and_relocates_jump_and_catch_positions
    # old PCs: 0 NOP, 1 JMP(+1 -> 5), 4 NOP, 5 STOP
    code = [0, 38, 0, 1, 0, 118].pack("C*")
    input = rite(code:, catches: [[1, 0, 5, 5]])

    result = RiteOpt::Rite::NopRemoval.call(input)
    document = RiteOpt::Rite::Parser.parse(result)
    root = document.sections.first.root
    rewritten_code = document.bytes(root.iseq.code_span)
    handler = root.iseq.catch_handlers.fetch(0)

    assert_equal [38, 0, 0, 118].pack("C*"), rewritten_code
    assert_equal 0, handler.begin_pos
    assert_equal 3, handler.end_pos
    assert_equal 3, handler.target
    assert_equal input.bytesize - 2, result.bytesize
    assert_equal result.bytesize, document.header.binary_size
  end

  def test_relocates_extended_jump_offset
    opcodes = RiteOpt::Rite::OPCODES.to_h { |opcode| [opcode.name, opcode] }
    ext1 = opcodes.fetch("EXT1")
    jmpif = opcodes.fetch("JMPIF")
    stop = opcodes.fetch("STOP")

    # old PCs: 0 NOP, 1 EXT1, 2 JMPIF R300,(+1 -> 8), 7 NOP, 8 STOP
    code = [0, ext1.code, jmpif.code, 1, 44, 0, 1, 0, stop.code].pack("C*")
    input = rite(code:)

    result = RiteOpt::Rite::NopRemoval.call(input)
    document = RiteOpt::Rite::Parser.parse(result)
    rewritten_code = document.bytes(document.sections.first.root.iseq.code_span)

    assert_equal [ext1.code, jmpif.code, 1, 44, 0, 0, stop.code].pack("C*"), rewritten_code
  end

  def test_is_idempotent
    input = rite(code: [0, 118].pack("C*"))

    first = RiteOpt::Rite::NopRemoval.call(input)
    second = RiteOpt::Rite::NopRemoval.call(first)

    assert_equal first, second
  end

  def test_rewrites_nested_irep_without_changing_parent_record_size
    child = irep_record(code: [0, 118].pack("C*"))
    input = rite(code: [118].pack("C*"), children: [child])

    before = RiteOpt::Rite::Parser.parse(input).sections.first.root
    result = RiteOpt::Rite::NopRemoval.call(input)
    after = RiteOpt::Rite::Parser.parse(result).sections.first.root

    assert_equal before.record_size, after.record_size
    assert_equal before.children.first.record_size - 1, after.children.first.record_size
    assert_equal input.bytesize - 1, result.bytesize
  end

  def test_rejects_debug_section
    input = rite(code: [118].pack("C*"), extra_sections: [section("DBG\0".b, "")])

    error = assert_raises(RiteOpt::Rite::UnsupportedRewrite) do
      RiteOpt::Rite::NopRemoval.call(input)
    end

    assert_equal "DBG section relocation is not implemented", error.message
  end

  private

  def rite(code:, catches: [], children: [], extra_sections: [])
    irep = section("IREP", "0400" + irep_record(code:, catches:, children:))
    footer = section("END\0".b, "")
    body = irep + extra_sections.join + footer
    header = "RITE0400" + [20 + body.bytesize].pack("N") + "MATZ0000"
    header + body
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
end
