# frozen_string_literal: true

module RiteOpt
  module Rite
    # One logical RITE instruction. source_span identifies the bytes in the
    # decoded RITE, including an EXT prefix when present. rite_extension keeps
    # that physical encoding so rewrites can preserve instruction width.
    Instruction = Data.define(:opcode, :rite_extension, :source_span, :operands) do
      def initialize(opcode:, source_span:, operands:, rite_extension: nil)
        super(
          opcode:,
          rite_extension: select_rite_extension(opcode, operands, preferred: rite_extension),
          source_span:,
          operands:
        )
      end

      def nop? = opcode.nop?
      def jump? = opcode.jump?
      def conditional_jump? = opcode.conditional_jump?
      def unwind_jump? = opcode.unwind_jump?
      def exit? = opcode.exit?
      def terminator? = opcode.terminator?

      OPERAND_INDEX = { a: 0, b: 1, c: 2 }.freeze

      def a = operand(:a)
      def b = operand(:b)
      def c = operand(:c)

      def operand(name) = operands[OPERAND_INDEX.fetch(name)]

      def with_operand(name, value)
        rewritten_operands = operands.dup
        rewritten_operands[OPERAND_INDEX.fetch(name)] = value
        with(operands: rewritten_operands.freeze, rite_extension:)
      end

      def pc = source_span.offset
      def next_pc = source_span.end_offset

      def jump_offset
        return unless jump?

        signed_16(operands.last)
      end

      def target_pc = jump_offset && next_pc + jump_offset

      def rite_byte_length
        opcode.byte_length(extension: rite_extension) + (rite_extension ? OPCODE_WIDTH : 0)
      end

      def in_place? = rite_byte_length == source_span.length

      # Encodes one logical instruction as RITE0400 bytes, preserving the
      # decoded EXT prefix when it can still represent the operands.
      def to_rite
        result = +"".b
        result << rite_extension.code if rite_extension
        result << opcode.code

        operands.each_index do |index|
          width = opcode.operand_width(index, extension: rite_extension)
          result << encode_operand(operands[index], width)
        end

        result.freeze
      end

      private

      def select_rite_extension(opcode, operands, preferred:)
        return preferred if operands_fit?(opcode, operands, preferred)

        required_rite_extension(opcode, operands)
      end

      def operands_fit?(opcode, operands, rite_extension)
        operands.each_index.all? do |index|
          value = operands.fetch(index)
          width = opcode.operand_width(index, extension: rite_extension)
          value.is_a?(Integer) && value >= 0 && value < (1 << (width * 8))
        end
      end

      def required_rite_extension(opcode, operands)
        first = extended_byte_operand?(opcode, operands, 0)
        second = extended_byte_operand?(opcode, operands, 1)

        name = if first && second
          "EXT3"
        elsif first
          "EXT1"
        elsif second
          "EXT2"
        end

        name && OPCODE_BY_NAME.fetch(name)
      end

      def extended_byte_operand?(opcode, operands, index)
        return false if index >= opcode.operand_count
        return false unless opcode.format[index] == "B"

        operands.fetch(index) > 0xff
      end

      def encode_operand(value, width)
        limit = 1 << (width * 8)
        unless value.is_a?(Integer) && value >= 0 && value < limit
          raise RangeError, "operand #{value.inspect} does not fit in #{width} bytes"
        end

        width.times.reverse_each.reduce(+"".b) do |bytes, index|
          bytes << ((value >> (index * 8)) & 0xff)
        end
      end

      def signed_16(value)
        sign_bit = 1 << 15
        value >= sign_bit ? value - (1 << 16) : value
      end
    end

    class InstructionDecodeError < StandardError
      attr_reader :pc

      def initialize(message, pc:)
        @pc = pc
        super("#{message} at code byte #{pc}")
      end
    end

    # Decodes RITE0400 into logical instructions. EXT1/2/3 are consumed as
    # prefixes and widen operands on the following instruction; they are not
    # exposed as independent instructions.
    class InstructionDecoder
      def self.decode(code) = new(code).decode

      def initialize(code)
        @code = code
      end

      def decode
        instructions = []
        pc = 0

        while pc < @code.bytesize
          instruction = decode_instruction(pc)
          instructions << instruction
          pc = instruction.next_pc
        end

        instructions.freeze
      end

      private

      def decode_instruction(start_pc)
        opcode, rite_extension, opcode_pc = decode_opcode(start_pc)
        end_pc = instruction_end_pc(start_pc, opcode_pc, opcode, rite_extension)

        Instruction.new(
          opcode:,
          rite_extension:,
          source_span: Span.new(offset: start_pc, length: end_pc - start_pc),
          operands: decode_operands(opcode_pc, opcode, rite_extension)
        )
      end

      def decode_opcode(start_pc)
        opcode = opcode_at(start_pc)
        return [opcode, nil, start_pc] unless opcode.ext?

        rite_extension = opcode
        opcode_pc = start_pc + OPCODE_WIDTH
        if opcode_pc >= @code.bytesize
          raise InstructionDecodeError.new(
            "extended opcode has no following instruction",
            pc: start_pc
          )
        end

        opcode = opcode_at(opcode_pc)
        if opcode.ext?
          raise InstructionDecodeError.new(
            "extended opcode cannot modify another extension",
            pc: start_pc
          )
        end

        [opcode, rite_extension, opcode_pc]
      end

      def instruction_end_pc(start_pc, opcode_pc, opcode, rite_extension)
        end_pc = opcode_pc + opcode.byte_length(extension: rite_extension)
        return end_pc if end_pc <= @code.bytesize

        raise InstructionDecodeError.new("instruction extends past ISEQ", pc: start_pc)
      end

      def decode_operands(opcode_pc, opcode, rite_extension)
        opcode.operand_count.times.map do |index|
          width = opcode.operand_width(index, extension: rite_extension)
          offset = opcode_pc + opcode.operand_offset(index, extension: rite_extension)
          read_operand_value(offset, width)
        end.freeze
      end

      def opcode_at(pc)
        code = @code.getbyte(pc)
        OPCODE_BY_CODE[code] || raise(
          InstructionDecodeError.new("invalid opcode #{code}", pc:)
        )
      end

      def read_operand_value(offset, width)
        width.times.reduce(0) do |value, index|
          (value << 8) | @code.getbyte(offset + index)
        end
      end
    end
  end
end
