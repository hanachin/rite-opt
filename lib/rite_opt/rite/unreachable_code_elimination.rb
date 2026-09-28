# frozen_string_literal: true

module RiteOpt
  module Rite
    # Replaces instructions in unreachable basic blocks with NOP bytes.
    #
    # This pass preserves every PC and RITE record size. NopRemoval can compact
    # the generated NOPs later and relocate jumps and catch positions.
    class UnreachableCodeElimination
      NOP_BYTE = [OPCODES.find(&:nop?).code].pack("C").freeze

      def self.call(source) = new(source).call

      def initialize(source)
        @document = Parser.parse(source.b)
      end

      def call
        section = ensure_rewrite_supported
        result = @document.source.dup

        each_nop_span(section.root) do |span|
          result[span.offset, span.length] = NOP_BYTE * span.length
        end

        result.freeze
      end

      private

      def ensure_rewrite_supported
        case @document.sections.grep(IrepSection)
        in [IrepSection(rite_version: "0400") => section]
          section
        in [IrepSection]
          raise UnsupportedRewrite, "RITE instruction version is not supported"
        else
          raise UnsupportedRewrite, "RITE must contain one IREP section"
        end
      end

      def each_nop_span(irep, &consumer)
        code = @document.bytes(irep.iseq.code_span)
        instructions = InstructionDecoder.decode(code)
        cfg = CFGBuilder.build(instructions, catch_handlers: irep.iseq.catch_handlers)
        reachable = {}

        cfg.each_reachable_block(0) do |block|
          reachable[block.start_pc] = true
        end

        cfg.blocks.each do |block|
          next if reachable.key?(block.start_pc)

          yield Span.new(
            offset: irep.iseq.code_span.offset + block.start_pc,
            length: block.length
          )
        end

        irep.children.each do |child|
          each_nop_span(child, &consumer)
        end
      end
    end
  end
end
