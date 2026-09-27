# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../lib/rite_opt/rite/reader"
require_relative "../../../lib/rite_opt/rite/opcodes"
require_relative "../../../lib/rite_opt/rite/instruction_decoder"

class InstructionDecoderTest < Minitest::Test
  def test_distinguishes_opcode_base_length_from_instruction_byte_length
    # MOVE R1, R2; EXT1; MOVE R300, R2; STOP
    code = [1, 1, 2, 115, 1, 1, 44, 2, 118].pack("C*")

    move, ext, extended_move, stop = RiteOpt::Rite::InstructionDecoder.decode(code)

    assert_equal 3, move.opcode.base_length
    assert_equal 3, move.byte_length
    assert_nil move.extension

    assert_equal 1, ext.opcode.base_length
    assert_equal 1, ext.byte_length
    assert ext.ext?

    assert_equal 3, extended_move.opcode.base_length
    assert_equal 4, extended_move.byte_length
    assert_equal "EXT1", extended_move.extension.name
    assert_equal 4, extended_move.pc
    assert_equal 8, stop.pc
  end

  def test_extension_bytes_are_precomputed
    opcodes = RiteOpt::Rite::OPCODES.to_h { |opcode| [opcode.name, opcode] }

    assert_equal 0, opcodes.fetch("MOVE").extension_bytes
    assert_equal 1, opcodes.fetch("EXT1").extension_bytes
    assert_equal 1, opcodes.fetch("EXT2").extension_bytes
    assert_equal 2, opcodes.fetch("EXT3").extension_bytes
  end

  def test_decodes_jump_target_pc
    # NOP; JMP(+1 -> 5); NOP; STOP
    code = [0, 38, 0, 1, 0, 118].pack("C*")

    _nop, jump, _dead_nop, _stop = RiteOpt::Rite::InstructionDecoder.decode(code)

    assert_equal 1, jump.jump_offset
    assert_equal 5, jump.target_pc
  end

  def test_decodes_extended_jump_target_pc
    opcodes = RiteOpt::Rite::OPCODES.to_h { |opcode| [opcode.name, opcode] }
    ext1 = opcodes.fetch("EXT1")
    jmpif = opcodes.fetch("JMPIF")
    nop = opcodes.fetch("NOP")
    stop = opcodes.fetch("STOP")
    code = [ext1.code, jmpif.code, 0, 1, 0, 1, nop.code, stop.code].pack("C*")

    _ext, jump, _nop, _stop = RiteOpt::Rite::InstructionDecoder.decode(code)

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
end
