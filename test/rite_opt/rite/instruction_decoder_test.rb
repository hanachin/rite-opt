# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../lib/rite_opt/rite/reader"
require_relative "../../../lib/rite_opt/rite/opcodes"
require_relative "../../../lib/rite_opt/rite/instruction_decoder"

class InstructionDecoderTest < Minitest::Test
  def test_decodes_extension_and_opcode_as_one_logical_instruction
    # MOVE R1, R2; EXT1 + MOVE R300, R2; STOP
    code = [1, 1, 2, 115, 1, 1, 44, 2, 118].pack("C*")

    move, extended_move, stop = RiteOpt::Rite::InstructionDecoder.decode(code)

    assert_equal 3, move.opcode.base_length
    assert_nil move.rite_extension
    assert_equal RiteOpt::Rite::Span.new(offset: 0, length: 3), move.source_span

    assert_equal "MOVE", extended_move.opcode.name
    assert_equal "EXT1", extended_move.rite_extension.name
    assert_equal RiteOpt::Rite::Span.new(offset: 3, length: 5), extended_move.source_span
    assert_equal 3, extended_move.pc
    assert_equal [300, 2], extended_move.operands
    assert_equal 8, stop.pc
  end

  def test_operand_widths_are_derived_from_format_and_extension
    opcodes = RiteOpt::Rite::OPCODE_BY_NAME
    move = opcodes.fetch("MOVE")

    assert_equal 1, move.operand_width(0)
    assert_equal 1, move.operand_width(1)
    assert_equal 2, move.operand_width(0, extension: opcodes.fetch("EXT1"))
    assert_equal 2, move.operand_width(1, extension: opcodes.fetch("EXT2"))
    assert_equal 2, move.operand_width(0, extension: opcodes.fetch("EXT3"))
    assert_equal 2, move.operand_width(1, extension: opcodes.fetch("EXT3"))
  end

  def test_instruction_span_covers_extension_and_opcode
    # MOVE R1, R2; EXT1 + MOVE R300, R2; STOP
    code = [1, 1, 2, 115, 1, 1, 44, 2, 118].pack("C*")

    move, extended_move, = RiteOpt::Rite::InstructionDecoder.decode(code)

    assert_equal RiteOpt::Rite::Span.new(offset: 0, length: 3), move.source_span
    assert_equal RiteOpt::Rite::Span.new(offset: 3, length: 5), extended_move.source_span
  end

  def test_decodes_raw_operands
    # MOVE R1, R2; EXT1 + MOVE R300, R2; STOP
    code = [1, 1, 2, 115, 1, 1, 44, 2, 118].pack("C*")

    move, extended_move, = RiteOpt::Rite::InstructionDecoder.decode(code)

    assert_equal [1, 2], move.operands
    assert_equal 1, move.a
    assert_equal 2, move.b
    assert_nil move.c
    assert_equal [300, 2], extended_move.operands
    assert_equal 300, extended_move.a
    assert_equal 2, extended_move.b
  end

  def test_to_rite_emits_required_extension
    move = RiteOpt::Rite::OPCODE_BY_NAME.fetch("MOVE")
    instruction = RiteOpt::Rite::Instruction.new(
      opcode: move,
      source_span: RiteOpt::Rite::Span.new(offset: 0, length: 5),
      operands: [300, 2].freeze
    )

    assert_equal [115, 1, 1, 44, 2], instruction.to_rite.bytes
  end

  def test_to_rite_uses_ext2_and_ext3_for_second_or_both_operands
    move = RiteOpt::Rite::OPCODE_BY_NAME.fetch("MOVE")

    ext2 = RiteOpt::Rite::Instruction.new(
      opcode: move,
      source_span: RiteOpt::Rite::Span.new(offset: 0, length: 5),
      operands: [1, 300].freeze
    )
    ext3 = RiteOpt::Rite::Instruction.new(
      opcode: move,
      source_span: RiteOpt::Rite::Span.new(offset: 0, length: 6),
      operands: [300, 301].freeze
    )

    assert_equal [116, 1, 1, 1, 44], ext2.to_rite.bytes
    assert_equal [117, 1, 1, 44, 1, 45], ext3.to_rite.bytes
  end

  def test_decode_and_to_rite_round_trip
    code = [1, 1, 2, 115, 1, 1, 44, 2, 118].pack("C*")

    encoded = RiteOpt::Rite::InstructionDecoder.decode(code).map(&:to_rite).join

    assert_equal code, encoded
  end

  def test_round_trip_preserves_redundant_extension
    code = [115, 1, 0, 1, 2].pack("C*")

    instruction = RiteOpt::Rite::InstructionDecoder.decode(code).fetch(0)

    assert_equal "EXT1", instruction.rite_extension.name
    assert_equal code, instruction.to_rite
  end

  def test_rite0400_formats_have_at_most_three_operands
    assert_operator RiteOpt::Rite::OPCODES.map(&:operand_count).max, :<=, 3
  end

  def test_decodes_jump_target_pc
    # NOP; JMP(+1 -> 5); NOP; STOP
    code = [0, 38, 0, 1, 0, 118].pack("C*")

    _nop, jump, _dead_nop, _stop = RiteOpt::Rite::InstructionDecoder.decode(code)

    assert_equal 1, jump.jump_offset
    assert_equal 5, jump.target_pc
  end

  def test_decodes_extended_jump_target_pc
    opcodes = RiteOpt::Rite::OPCODE_BY_NAME
    ext1 = opcodes.fetch("EXT1")
    jmpif = opcodes.fetch("JMPIF")
    nop = opcodes.fetch("NOP")
    stop = opcodes.fetch("STOP")
    code = [ext1.code, jmpif.code, 0, 1, 0, 1, nop.code, stop.code].pack("C*")

    jump, _nop, _stop = RiteOpt::Rite::InstructionDecoder.decode(code)

    assert_equal 0, jump.pc
    assert_equal RiteOpt::Rite::Span.new(offset: 0, length: 6), jump.source_span
    assert_equal 1, jump.jump_offset
    assert_equal 7, jump.target_pc
  end

  def test_decodes_backward_jump_target_pc
    # NOP; JMP(-4 -> 0); STOP
    code = [0, 38, 0xff, 0xfc, 118].pack("C*")

    _nop, jump, _stop = RiteOpt::Rite::InstructionDecoder.decode(code)

    assert_equal(-4, jump.jump_offset)
    assert_equal 0, jump.target_pc
  end

  def test_rejects_trailing_extension
    code = [115].pack("C*")

    error = assert_raises(RiteOpt::Rite::InstructionDecodeError) do
      RiteOpt::Rite::InstructionDecoder.decode(code)
    end

    assert_equal 0, error.pc
    assert_match(/no following instruction/, error.message)
  end

  def test_rejects_extension_chain
    code = [115, 116, 1, 1, 2].pack("C*")

    error = assert_raises(RiteOpt::Rite::InstructionDecodeError) do
      RiteOpt::Rite::InstructionDecoder.decode(code)
    end

    assert_equal 0, error.pc
    assert_match(/cannot modify another extension/, error.message)
  end
end
