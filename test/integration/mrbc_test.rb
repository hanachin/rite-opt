# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../../lib/rite_opt"

class MrbcIntegrationTest < Minitest::Test
  FIXTURES = File.expand_path("../fixtures/integration", __dir__)
  EXECUTABLE = File.expand_path("../../exe/rite-opt", __dir__)
  CONTROL_FLOW_OUTPUT = "redo,next,raise,rescue:boom,ensure,catch,throw,after-catch:42\n"

  def setup
    @mrbc = executable("MRBC", "mrbc")
    @mruby = executable("MRUBY", "mruby")
    skip "mrbc is not available" unless @mrbc
    skip "mruby is not available" unless @mruby
  end

  def test_debug_removal_reduces_mrbc_debug_output
    source = compile("metadata.rb", "-g")
    before = parse(source)

    assert before.sections.any? { |section| section in RiteOpt::Rite::DebugSection }

    optimized = RiteOpt::Rite::DebugRemoval.call(source)
    after = parse(optimized)

    assert_operator optimized.bytesize, :<, source.bytesize
    refute after.sections.any? { |section| section in RiteOpt::Rite::DebugSection }
    assert_equal execute(source), execute(optimized)
  end

  def test_lvar_removal_reduces_mrbc_output
    source = compile("metadata.rb")
    before = parse(source)

    assert before.sections.any? { |section| section in RiteOpt::Rite::LvarSection }

    optimized = RiteOpt::Rite::LvarRemoval.call(source)
    after = parse(optimized)

    assert_operator optimized.bytesize, :<, source.bytesize
    refute after.sections.any? { |section| section in RiteOpt::Rite::LvarSection }
    assert_equal execute(source), execute(optimized)
  end

  def test_unreachable_code_elimination_marks_real_mrbc_dead_block_as_nops
    source = compile("unreachable.rb")
    before = parse(source)
    method_irep = root_irep(before).children.fetch(0)
    before_instructions = instructions(before, method_irep)
    cfg = RiteOpt::Rite::CFGBuilder.build(
      before_instructions,
      catch_handlers: method_irep.iseq.catch_handlers
    )

    reachable = cfg.each_reachable_block(0).to_h { |block| [block.start_pc, true] }
    assert cfg.blocks.any? { |block| !reachable.key?(block.start_pc) }
    before_execution = execute(source)
    assert_equal ["42\n", ""], before_execution

    eliminated = RiteOpt::Rite::UnreachableCodeElimination.call(source)
    after_elimination = parse(eliminated)
    eliminated_method = root_irep(after_elimination).children.fetch(0)

    assert_equal source.bytesize, eliminated.bytesize
    assert_operator instructions(after_elimination, eliminated_method).count(&:nop?), :>, 0
    assert_equal before_execution, execute(eliminated)

    optimized = RiteOpt::Rite::NopRemoval.call(eliminated)

    assert_operator optimized.bytesize, :<, source.bytesize
    assert_equal before_execution, execute(optimized)
  end

  def test_nop_removal_relocates_real_mrbc_control_flow
    source = compile("control_flow.rb")
    before = parse(source)
    before_root = root_irep(before)
    before_instructions = instructions(before, before_root)
    before_jumps = jump_offsets(before, before_root)
    before_catches = catch_positions(before_root)

    assert_operator before_instructions.count(&:nop?), :>, 0
    assert_operator before_jumps.length, :>, 0
    assert_operator before_catches.length, :>, 0
    assert_equal CONTROL_FLOW_OUTPUT, execute(source).first

    optimized = RiteOpt::Rite::NopRemoval.call(source)
    after = parse(optimized)
    after_root = root_irep(after)

    assert_operator optimized.bytesize, :<, source.bytesize
    assert_equal 0, instructions(after, after_root).count(&:nop?)
    refute_equal before_jumps, jump_offsets(after, after_root)
    refute_equal before_catches, catch_positions(after_root)
    assert_equal execute(source), execute(optimized)
  end

  def test_rite_opt_executes_relocated_jump_and_catch_paths
    source = compile("control_flow.rb", "-g")
    before = parse(source)
    before_root = root_irep(before)
    before_jumps = jump_offsets(before, before_root)
    before_catches = catch_positions(before_root)

    assert before.sections.any? { |section| section in RiteOpt::Rite::DebugSection }
    assert before.sections.any? { |section| section in RiteOpt::Rite::LvarSection }
    assert_operator instructions(before, before_root).count(&:nop?), :>, 0
    before_execution = execute(source)
    assert_equal [CONTROL_FLOW_OUTPUT, ""], before_execution

    optimized = optimize_with_cli(source)
    after = parse(optimized)
    after_root = root_irep(after)

    refute after.sections.any? { |section| section in RiteOpt::Rite::DebugSection }
    refute after.sections.any? { |section| section in RiteOpt::Rite::LvarSection }
    assert_equal 0, instructions(after, after_root).count(&:nop?)
    refute_equal before_jumps, jump_offsets(after, after_root)
    refute_equal before_catches, catch_positions(after_root)

    after_execution = execute(optimized)
    assert_equal before_execution, after_execution

    stdout, stderr = after_execution
    assert_equal CONTROL_FLOW_OUTPUT, stdout
    assert_equal "", stderr
    assert_includes stdout, "redo"
    assert_includes stdout, "next"
    assert_includes stdout, "raise"
    assert_includes stdout, "rescue:boom"
    assert_includes stdout, "ensure"
    assert_includes stdout, "catch"
    assert_includes stdout, "throw"
    assert_includes stdout, "after-catch:42"
    refute_includes stdout, "after-throw"
  end

  private

  def executable(env_name, command)
    configured = ENV[env_name]
    return configured if configured && File.executable?(configured)

    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
      path = File.join(directory, command)
      return path if File.executable?(path)
    end

    nil
  end

  def compile(fixture, *options)
    source = File.join(FIXTURES, fixture)

    Dir.mktmpdir("rite-opt-mrbc") do |directory|
      output = File.join(directory, "program.mrb")
      stdout, stderr, status = Open3.capture3(@mrbc, *options, "-o", output, source)
      assert status.success?, "mrbc failed:\n#{stdout}#{stderr}"
      return File.binread(output)
    end
  end

  def optimize_with_cli(bytes)
    Dir.mktmpdir("rite-opt-cli") do |directory|
      input = File.join(directory, "program.mrb")
      output = File.join(directory, "program.opt.mrb")
      File.binwrite(input, bytes)

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, EXECUTABLE, "-o", output, input
      )
      assert status.success?, "rite-opt failed:\n#{stdout}#{stderr}"
      return File.binread(output)
    end
  end

  def execute(bytes)
    Dir.mktmpdir("rite-opt-mruby") do |directory|
      path = File.join(directory, "program.mrb")
      File.binwrite(path, bytes)
      stdout, stderr, status = Open3.capture3(@mruby, "-b", path)
      assert status.success?, "mruby failed:\n#{stdout}#{stderr}"
      return [stdout, stderr]
    end
  end

  def parse(bytes) = RiteOpt::Rite::Parser.parse(bytes)

  def root_irep(document)
    document.sections.grep(RiteOpt::Rite::IrepSection).fetch(0).root
  end

  def instructions(document, irep)
    code = document.bytes(irep.iseq.code_span)
    RiteOpt::Rite::InstructionDecoder.decode(code)
  end

  def jump_offsets(document, irep)
    code = document.bytes(irep.iseq.code_span)

    instructions(document, irep).filter_map do |instruction|
      next unless instruction.jump?

      span = RiteOpt::Rite::InstructionPlacement.new(
        instruction:,
        pc: instruction.pc
      ).old_jump_offset_span
      code.byteslice(span.offset, span.length).unpack1("s>")
    end
  end

  def catch_positions(irep)
    irep.iseq.catch_handlers.map do |handler|
      [handler.begin_pos, handler.end_pos, handler.target]
    end
  end
end
