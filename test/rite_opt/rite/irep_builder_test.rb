# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../lib/rite_opt/rite/reader"
require_relative "../../../lib/rite_opt/rite/opcodes"
require_relative "../../../lib/rite_opt/rite/instruction_decoder"
require_relative "../../../lib/rite_opt/rite/rewrite_error"
require_relative "../../../lib/rite_opt/rite/irep_builder"

class IrepBuilderTest < Minitest::Test
  def test_instruction_placement_maps_jump_offset_span
    opcodes = RiteOpt::Rite::OPCODES.to_h { |opcode| [opcode.name, opcode] }
    ext1 = opcodes.fetch("EXT1")
    jmpif = opcodes.fetch("JMPIF")
    code = [ext1.code, jmpif.code, 1, 44, 0, 2].pack("C*")
    instruction = RiteOpt::Rite::InstructionDecoder.decode(code).fetch(0)
    placement = RiteOpt::Rite::InstructionPlacement.new(instruction:, pc: 10)

    assert_equal RiteOpt::Rite::Span.new(offset: 4, length: 2), placement.old_jump_offset_span
    assert_equal RiteOpt::Rite::Span.new(offset: 14, length: 2), placement.new_jump_offset_span
  end
end
