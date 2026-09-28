# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../lib/rite_opt/rite/opcodes"
require_relative "../../../lib/rite_opt/rite/instruction_decoder"
require_relative "../../../lib/rite_opt/rite/effect_analysis"
require_relative "../../../lib/rite_opt/rite/cfg"
require_relative "../../../lib/rite_opt/rite/liveness"

class LivenessTest < Minitest::Test
  def test_unions_live_registers_from_branch_successors
    # PCs: 0 JMPIF R1,+2 -> 6; 4 RETURN R2; 6 RETURN R3
    code = [
      opcode("JMPIF"), 1, 0, 2,
      opcode("RETURN"), 2,
      opcode("RETURN"), 3
    ].pack("C*")

    analysis, cfg = analyze(code)
    entry, fallthrough, branch = cfg.blocks

    assert_registers [1, 2, 3], analysis.live_in(entry)
    assert_registers [2, 3], analysis.live_out(entry)
    assert_registers [2], analysis.live_in(fallthrough)
    assert_registers [3], analysis.live_in(branch)
  end

  def test_iterates_until_loop_liveness_converges
    # PCs: 0 MOVE R2,R1; 3 JMP -6 -> 0
    code = [
      opcode("MOVE"), 2, 1,
      opcode("JMP"), 0xff, 0xfa
    ].pack("C*")

    analysis, cfg = analyze(code)
    block = cfg.blocks.fetch(0)

    assert_registers [1], analysis.live_in(block)
    assert_registers [1], analysis.live_out(block)
  end

  def test_uses_exit_live_as_terminal_boundary
    code = [opcode("RETNIL")].pack("C*")
    instructions = RiteOpt::Rite::InstructionDecoder.decode(code)
    cfg = RiteOpt::Rite::CFGBuilder.build(instructions, catch_handlers: [])
    effect_analysis = RiteOpt::Rite::EffectAnalysis.new(nregs: 4)
    analysis = RiteOpt::Rite::Liveness.analyze(
      cfg:,
      instructions:,
      effect_analysis:,
      exit_live: register_set(1, 3)
    )

    block = cfg.blocks.fetch(0)
    assert_registers [1, 3], analysis.live_in(block)
    assert_registers [1, 3], analysis.live_out(block)
  end

  def test_keeps_exit_boundary_when_only_exception_successor_exists
    # PCs: 0 RETURN R1; 2 JMP -3 -> 2
    code = [
      opcode("RETURN"), 1,
      opcode("JMP"), 0xff, 0xfd
    ].pack("C*")
    instructions = RiteOpt::Rite::InstructionDecoder.decode(code)
    handler = RiteOpt::Rite::CatchHandler.new(
      type: 1,
      begin_pos: 0,
      end_pos: 2,
      target: 2,
      span: nil
    )
    cfg = RiteOpt::Rite::CFGBuilder.build(instructions, catch_handlers: [handler])
    effect_analysis = RiteOpt::Rite::EffectAnalysis.new(nregs: 4)
    analysis = RiteOpt::Rite::Liveness.analyze(
      cfg:,
      instructions:,
      effect_analysis:,
      exit_live: register_set(3)
    )

    assert_registers [3], analysis.live_out(cfg.blocks.fetch(0))
  end

  private

  def analyze(code)
    instructions = RiteOpt::Rite::InstructionDecoder.decode(code)
    cfg = RiteOpt::Rite::CFGBuilder.build(instructions, catch_handlers: [])
    effect_analysis = RiteOpt::Rite::EffectAnalysis.new(nregs: 8)
    [RiteOpt::Rite::Liveness.analyze(cfg:, instructions:, effect_analysis:), cfg]
  end

  def assert_registers(expected, bits)
    actual = 8.times.select { |register| (bits & (1 << register)) != 0 }
    assert_equal expected, actual
  end

  def register_set(*registers)
    registers.reduce(0) { |bits, register| bits | (1 << register) }
  end

  def opcode(name)
    RiteOpt::Rite::OPCODES.find { |candidate| candidate.name == name }.code
  end
end
