# frozen_string_literal: true

module RiteOpt
  module Rite
    # Mutable editing state for one parsed IREP tree.
    #
    # The parsed IREP remains the source of lossless bytes. Only instructions are
    # mutable. #build derives PC relocation, catch positions, ISEQ length, and
    # record sizes from the edited instruction lists.
    InstructionPlacement = Data.define(:instruction, :pc) do
      JUMP_OFFSET_LENGTH = 2

      def old_jump_offset_span = jump_offset_span(instruction.pc)
      def new_jump_offset_span = jump_offset_span(pc)

      private

      def jump_offset_span(at)
        Span.new(
          offset: at + instruction.byte_length - JUMP_OFFSET_LENGTH,
          length: JUMP_OFFSET_LENGTH
        )
      end
    end

    class IrepBuilder
      CodeLayout = Data.define(:code, :pc_map, :placements)

      attr_reader :instructions, :children

      def initialize(document, irep)
        @document = document
        @original_irep = irep
        @original_code = raw(irep.iseq.code_span)
        @original_instructions = InstructionDecoder.decode(@original_code)
        @instructions = @original_instructions.dup
        @children = irep.children.map { |child| self.class.new(document, child) }
      end

      def each_irep(&block)
        return enum_for(__method__) unless block

        yield self
        children.each { |child| child.each_irep(&block) }
        self
      end

      def build
        layout = layout_code
        iseq = build_iseq(layout)
        header = build_header
        pool = build_pool
        symbols = build_symbols
        record_tail = build_record_tail

        record_size =
          Irep.size_field_size +
          header.bytesize +
          iseq.bytesize +
          pool.bytesize +
          symbols.bytesize +
          record_tail.bytesize

        out = +[record_size].pack("N")
        out << header << iseq << pool << symbols << record_tail
        children.each { |child| out << child.build }
        out
      end

      private

      def build_header
        [@original_irep.nlocals, @original_irep.nregs, children.length].pack("n3")
      end

      def build_pool = raw(@original_irep.pool.span)

      def build_symbols = raw(@original_irep.symbols.span)

      def build_record_tail = raw(@original_irep.record_tail_span)

      def layout_code
        layout = place_instructions
        relocate_jumps(layout)

        layout.code.freeze
        layout.pc_map.freeze
        layout.placements.freeze
        layout
      end

      def place_instructions
        kept = instructions.to_h { |instruction| [instruction.pc, instruction] }
        pc_map = {}
        placements = []
        code = +"".b

        @original_instructions.each do |instruction|
          pc_map[instruction.pc] = code.bytesize
          next unless kept.key?(instruction.pc)

          new_pc = code.bytesize
          code << @original_code.byteslice(instruction.pc, instruction.byte_length)
          placements << InstructionPlacement.new(instruction:, pc: new_pc)
        end
        pc_map[@original_code.bytesize] = code.bytesize

        CodeLayout.new(code:, pc_map:, placements:)
      end

      def relocate_jumps(layout)
        layout.placements.each do |placement|
          instruction = placement.instruction
          next unless instruction.jump?

          new_target = relocate_pc(layout.pc_map, instruction.target_pc)
          new_offset = new_target - (placement.pc + instruction.byte_length)

          unless (-32_768..32_767).cover?(new_offset)
            raise UnsupportedRewrite, "jump offset overflow after IREP rewrite"
          end

          new_span = placement.new_jump_offset_span
          layout.code[new_span.offset, new_span.length] = [new_offset].pack("s>")
        end
      end

      def build_iseq(layout)
        out = +[@original_irep.iseq.clen].pack("n")
        out << [layout.code.bytesize].pack("N")
        out << layout.code
        out << build_catch_handlers(layout.pc_map)
        out
      end

      def build_catch_handlers(pc_map)
        @original_irep.iseq.catch_handlers.map do |handler|
          [
            handler.type,
            relocate_pc(pc_map, handler.begin_pos),
            relocate_pc(pc_map, handler.end_pos),
            relocate_pc(pc_map, handler.target)
          ].pack("CNNN")
        end.join
      end

      def relocate_pc(pc_map, pc)
        mapped = pc_map[pc]
        return mapped if mapped

        raise UnsupportedRewrite,
              "PC #{pc} is not an instruction boundary (ISEQ size #{@original_code.bytesize})"
      end

      def original_code_bytes(span) = @original_code.byteslice(span.offset, span.length)

      def raw(span) = @document.bytes(span)
    end
  end
end
