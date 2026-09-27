# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../lib/rite_opt/rite/reader"
require_relative "../../../lib/rite_opt/rite/parser"
require_relative "../../../lib/rite_opt/rite/opcodes"
require_relative "../../../lib/rite_opt/rite/instruction_decoder"
require_relative "../../../lib/rite_opt/rite/cfg"

class CFGTest < Minitest::Test
  def test_builds_conditional_branch_and_fallthrough_edges
    # PCs: 0 LOADI_1 R1; 2 JMPNOT R1,+1 -> 7; 6 RETTRUE; 7 RETFALSE
    code = [
      opcode("LOADI_1"), 1,
      opcode("JMPNOT"), 1, 0, 1,
      opcode("RETTRUE"),
      opcode("RETFALSE")
    ].pack("C*")

    cfg = build_cfg(code)

    assert_equal [[0, 6], [6, 7], [7, 8]], block_ranges(cfg)
    assert_equal [
      [0, 7, :branch],
      [0, 6, :fallthrough]
    ], edge_rows(cfg)
  end

  def test_keeps_code_after_exit_as_a_separate_unreachable_block
    # PCs: 0 RETURN R1; 2 LOADI_1 R1; 4 RETURN R1
    code = [
      opcode("RETURN"), 1,
      opcode("LOADI_1"), 1,
      opcode("RETURN"), 1
    ].pack("C*")

    cfg = build_cfg(code)

    assert_equal [[0, 2], [2, 6]], block_ranges(cfg)
    assert_empty cfg.edges
  end

  def test_distinguishes_unwind_jump_from_normal_jump
    # PCs: 0 JMPUW,+1 -> 4; 3 NOP; 4 STOP
    code = [opcode("JMPUW"), 0, 1, opcode("NOP"), opcode("STOP")].pack("C*")

    cfg = build_cfg(code)

    assert_equal [[0, 3], [3, 4], [4, 5]], block_ranges(cfg)
    assert_equal [[0, 4, :unwind], [3, 4, :fallthrough]], edge_rows(cfg)
  end

  def test_splits_at_catch_boundaries_and_adds_exception_edges
    # PCs: 0 NOP; 1 NOP; 2 RETURN R1; 4 STOP
    code = [opcode("NOP"), opcode("NOP"), opcode("RETURN"), 1, opcode("STOP")].pack("C*")
    handler = RiteOpt::Rite::CatchHandler.new(
      type: 1,
      begin_pos: 1,
      end_pos: 4,
      target: 4,
      span: nil
    )

    cfg = build_cfg(code, catch_handlers: [handler])

    assert_equal [[0, 1], [1, 4], [4, 5]], block_ranges(cfg)
    assert_equal [
      [0, 1, :fallthrough],
      [1, 4, :exception]
    ], edge_rows(cfg)
  end

  def test_opcode_control_flow_classification
    assert opcode_object("JMPIF").conditional_jump?
    assert opcode_object("JMPUW").unwind_jump?
    assert opcode_object("RETURN").exit?
    assert opcode_object("STOP").terminator?
    refute opcode_object("MOVE").terminator?
  end

  private

  def build_cfg(code, catch_handlers: [])
    instructions = RiteOpt::Rite::InstructionDecoder.decode(code)
    RiteOpt::Rite::CFGBuilder.build(instructions, catch_handlers:)
  end

  def block_ranges(cfg)
    cfg.blocks.map { |block| [block.start_pc, block.end_pc] }
  end

  def edge_rows(cfg)
    cfg.edges.map { |edge| [edge.from_pc, edge.to_pc, edge.kind] }
  end

  def opcode(name)
    opcode_object(name).code
  end

  def opcode_object(name)
    RiteOpt::Rite::OPCODES.find { |opcode| opcode.name == name }
  end
end
