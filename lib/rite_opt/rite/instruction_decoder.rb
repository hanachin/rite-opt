# frozen_string_literal: true

module RiteOpt
  module Rite
    Instruction = Data.define(:opcode, :pc, :byte_length, :extension, :jump_offset) do
      def nop? = opcode.nop?
      def ext? = opcode.ext?
      def jump? = opcode.jump?
      def conditional_jump? = opcode.conditional_jump?
      def unwind_jump? = opcode.unwind_jump?
      def exit? = opcode.exit?
      def terminator? = opcode.terminator?
      def next_pc = pc + byte_length
      def target_pc = jump_offset && next_pc + jump_offset
    end

    class InstructionDecodeError < StandardError
      attr_reader :pc

      def initialize(message, pc:)
        @pc = pc
        super("#{message} at code byte #{pc}")
      end
    end

    # Decodes RITE0400 instruction boundaries. EXT1/2/3 are kept as their own
    # instructions. The following instruction records the extension and its
    # resulting encoded byte length.
    class InstructionDecoder
      def self.decode(code) = new(code).decode

      def initialize(code)
        @code = code
      end

      def decode
        instructions = []
        pc = 0

        while pc < @code.bytesize
          pc = decode_at(pc) { |instruction| instructions << instruction }
        end

        instructions.freeze
      end

      private

      def decode_at(pc)
        extension = nil

        loop do
          instruction = decode_instruction(pc, extension:)
          yield instruction
          pc = instruction.next_pc

          return pc unless instruction.ext?

          if pc >= @code.bytesize
            raise InstructionDecodeError.new(
              "extended opcode has no following instruction",
              pc: instruction.pc
            )
          end

          extension = instruction.opcode
        end
      end

      def decode_instruction(pc, extension: nil)
        code = @code.getbyte(pc)
        opcode = OPCODE_BY_CODE[code]
        raise InstructionDecodeError.new("invalid opcode #{code}", pc:) unless opcode

        byte_length = opcode.base_length
        byte_length += extension.extension_bytes if extension

        if pc + byte_length > @code.bytesize
          raise InstructionDecodeError.new("instruction extends past ISEQ", pc:)
        end

        jump_offset =
          if opcode.jump?
            @code.byteslice(pc + byte_length - 2, 2).unpack1("s>")
          end

        Instruction.new(opcode:, pc:, byte_length:, extension:, jump_offset:)
      end
    end
  end
end
