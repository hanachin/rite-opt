# frozen_string_literal: true

module RiteOpt
  module Rite
    CONDITIONAL_JUMP_NAMES = %w[JMPIF JMPNOT JMPNIL].freeze
    EXIT_NAMES = %w[
      CALL
      RETURN RETURN_BLK
      RETSELF RETNIL RETTRUE RETFALSE
      BREAK ERR STOP
    ].freeze

    OPCODE_WIDTH = 1
    OPERAND_WIDTHS = {
      "B" => 1,
      "S" => 2,
      "W" => 3
    }.freeze

    Opcode = Data.define(:code, :name, :format) do
      def nop? = name == "NOP"
      def ext? = name.start_with?("EXT")
      def jump? = name.start_with?("JMP")
      def conditional_jump? = CONDITIONAL_JUMP_NAMES.include?(name)
      def unwind_jump? = name == "JMPUW"
      def exit? = EXIT_NAMES.include?(name)
      def terminator? = jump? || exit?

      def operand_count = format == "Z" ? 0 : format.length

      def operand_width(index, extension: nil)
        kind = format[index]
        width = OPERAND_WIDTHS.fetch(kind)
        width += extension.extension_width(index) if kind == "B" && extension
        width
      end

      def operand_offset(index, extension: nil)
        OPCODE_WIDTH + index.times.sum { |operand_index| operand_width(operand_index, extension:) }
      end

      def base_length = byte_length

      def byte_length(extension: nil)
        OPCODE_WIDTH + operand_count.times.sum { |index| operand_width(index, extension:) }
      end

      def extension_width(index)
        case name
        when "EXT1"
          index.zero? ? 1 : 0
        when "EXT2"
          index == 1 ? 1 : 0
        when "EXT3"
          index < 2 ? 1 : 0
        else
          0
        end
      end
    end

    # RITE0400 opcode order and operand formats.
    OPCODES = [
      ["NOP", "Z"], ["MOVE", "BB"], ["LOADL", "BB"], ["LOADI8", "BB"],
      ["LOADINEG", "BB"], ["LOADI__1", "B"], ["LOADI_0", "B"], ["LOADI_1", "B"],
      ["LOADI_2", "B"], ["LOADI_3", "B"], ["LOADI_4", "B"], ["LOADI_5", "B"],
      ["LOADI_6", "B"], ["LOADI_7", "B"], ["LOADI16", "BS"], ["LOADI32", "BSS"],
      ["LOADSYM", "BB"], ["LOADNIL", "B"], ["LOADSELF", "B"], ["LOADTRUE", "B"],
      ["LOADFALSE", "B"], ["GETGV", "BB"], ["SETGV", "BB"], ["GETSV", "BB"],
      ["SETSV", "BB"], ["GETIV", "BB"], ["SETIV", "BB"], ["GETCV", "BB"],
      ["SETCV", "BB"], ["GETCONST", "BB"], ["SETCONST", "BB"], ["GETMCNST", "BB"],
      ["SETMCNST", "BB"], ["GETUPVAR", "BBB"], ["SETUPVAR", "BBB"], ["GETIDX", "B"],
      ["GETIDX0", "BB"], ["SETIDX", "B"], ["JMP", "S"], ["JMPIF", "BS"],
      ["JMPNOT", "BS"], ["JMPNIL", "BS"], ["JMPUW", "S"], ["EXCEPT", "B"],
      ["RESCUE", "BB"], ["RAISEIF", "B"], ["MATCHERR", "B"], ["SSEND", "BBB"],
      ["SSEND0", "BB"], ["SSENDB", "BBB"], ["SEND", "BBB"], ["SEND0", "BB"],
      ["SENDB", "BBB"], ["CALL", "Z"], ["BLKCALL", "BB"], ["SUPER", "BB"],
      ["ARGARY", "BS"], ["ENTER", "W"], ["KEY_P", "BB"], ["KEYEND", "Z"],
      ["KARG", "BB"], ["RETURN", "B"], ["RETURN_BLK", "B"], ["RETSELF", "Z"],
      ["RETNIL", "Z"], ["RETTRUE", "Z"], ["RETFALSE", "Z"], ["BREAK", "B"],
      ["BLKPUSH", "BS"], ["ADD", "B"], ["ADDI", "BB"], ["SUB", "B"],
      ["SUBI", "BB"], ["ADDILV", "BBB"], ["SUBILV", "BBB"], ["MUL", "B"],
      ["DIV", "B"], ["EQ", "B"], ["LT", "B"], ["LE", "B"],
      ["GT", "B"], ["GE", "B"], ["ARRAY", "BB"], ["ARRAY2", "BBB"],
      ["ARYCAT", "B"], ["ARYPUSH", "BB"], ["ARYSPLAT", "B"], ["AREF", "BBB"],
      ["ASET", "BBB"], ["APOST", "BBB"], ["INTERN", "B"], ["SYMBOL", "BB"],
      ["STRING", "BB"], ["STRCAT", "B"], ["HASH", "BB"], ["HASHADD", "BB"],
      ["HASHCAT", "B"], ["LAMBDA", "BB"], ["BLOCK", "BB"], ["METHOD", "BB"],
      ["RANGE_INC", "B"], ["RANGE_EXC", "B"], ["OCLASS", "B"], ["CLASS", "BB"],
      ["MODULE", "BB"], ["EXEC", "BB"], ["DEF", "BB"], ["TDEF", "BBB"],
      ["SDEF", "BBB"], ["ALIAS", "BB"], ["UNDEF", "B"], ["SCLASS", "B"],
      ["TCLASS", "B"], ["DEBUG", "BBB"], ["ERR", "B"], ["EXT1", "Z"],
      ["EXT2", "Z"], ["EXT3", "Z"], ["STOP", "Z"]
    ].each_with_index.map do |(name, format), code|
      Opcode.new(code:, name:, format:)
    end.freeze

    OPCODE_BY_CODE = OPCODES.to_h { |opcode| [opcode.code, opcode] }.freeze
    OPCODE_BY_NAME = OPCODES.to_h { |opcode| [opcode.name, opcode] }.freeze
  end
end
