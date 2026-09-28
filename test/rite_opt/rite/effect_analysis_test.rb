# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../lib/rite_opt/rite/opcodes"
require_relative "../../../lib/rite_opt/rite/instruction_decoder"
require_relative "../../../lib/rite_opt/rite/effect_analysis"

class EffectAnalysisTest < Minitest::Test
  def test_move_reads_source_and_defines_destination
    effect = analysis.effect_for(instruction("MOVE", 2, 1))

    assert effect.uses?(1)
    refute effect.uses?(2)
    assert effect.defines?(2)
    refute effect.defines?(1)
    assert effect.register_assignment_only?
    assert_equal [:b], effect.use_operands
    assert_equal({ destination: :a, source: :b }, effect.copy)
    assert effect.modeled?
  end

  def test_load_defines_destination_without_reading_a_register
    effect = analysis.effect_for(instruction("LOADI_1", 3))

    assert_equal 0, effect.uses
    assert effect.defines?(3)
    assert effect.register_assignment_only?
  end

  def test_loadself_defines_destination_without_reading_a_register
    effect = analysis.effect_for(instruction("LOADSELF", 2))

    assert_equal 0, effect.uses
    assert effect.defines?(2)
    assert effect.register_assignment_only?
  end

  def test_conditional_jump_reads_condition_register
    effect = analysis.effect_for(instruction("JMPIF", 4, 0))

    assert effect.uses?(4)
    assert_equal 0, effect.defs
    refute effect.register_assignment_only?
  end

  def test_return_reads_return_register
    effect = analysis.effect_for(instruction("RETURN", 5))

    assert effect.uses?(5)
    assert_equal 0, effect.defs
    refute effect.register_assignment_only?
  end

  def test_instruction_without_register_operands_has_no_register_use_or_def
    effect = analysis.effect_for(instruction("JMP", 0))

    assert_equal 0, effect.uses
    assert_equal 0, effect.defs
    refute effect.register_assignment_only?
  end

  def test_potentially_raising_instruction_is_conservative
    effect = analysis.effect_for(instruction("RAISEIF", 4))

    assert_equal((1 << 8) - 1, effect.uses)
    assert_equal 0, effect.defs
    refute effect.register_assignment_only?
    refute effect.modeled?
  end

  def test_unknown_instruction_conservatively_reads_every_register
    effect = analysis.effect_for(instruction("SEND", 1, 0, 0))

    assert_equal((1 << 8) - 1, effect.uses)
    assert_equal 0, effect.defs
    refute effect.register_assignment_only?
    assert_empty effect.use_operands
    refute effect.modeled?
  end

  private

  def analysis = RiteOpt::Rite::EffectAnalysis.new(nregs: 8)

  def instruction(name, *operands)
    opcode = RiteOpt::Rite::OPCODES.find { |candidate| candidate.name == name }
    RiteOpt::Rite::Instruction.new(
      opcode:,
      source_span: RiteOpt::Rite::Span.new(offset: 0, length: opcode.base_length),
      operands: operands.freeze
    )
  end
end
