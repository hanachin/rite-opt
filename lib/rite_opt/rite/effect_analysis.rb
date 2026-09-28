# frozen_string_literal: true

module RiteOpt
  module Rite
    Effect = Data.define(:uses, :defs, :register_assignment_only) do
      def uses?(register) = (uses & (1 << register)) != 0
      def defines?(register) = (defs & (1 << register)) != 0
      def register_assignment_only? = register_assignment_only
    end

    # Describes the effects of one instruction that are relevant to analysis.
    #
    # Unknown instructions conservatively read every register and define none.
    # This lets data-flow analyses start with a small verified opcode set without
    # treating an unmodelled instruction as proof that an earlier value is dead.
    #
    # register_assignment_only? is true only when the instruction is known to
    # have no execution effect other than assigning its destination register.
    class EffectAnalysis
      NONE = 0

      LOAD_NAMES = %w[
        LOADL
        LOADI8 LOADINEG LOADI__1 LOADI_0 LOADI_1 LOADI_2 LOADI_3
        LOADI_4 LOADI_5 LOADI_6 LOADI_7 LOADI16 LOADI32
        LOADSYM LOADNIL LOADTRUE LOADFALSE
      ].freeze
      USE_A_NAMES = %w[JMPIF JMPNOT JMPNIL RETURN RETURN_BLK BREAK].freeze
      NO_REGISTER_NAMES = %w[NOP JMP JMPUW RETNIL RETTRUE RETFALSE STOP].freeze

      def initialize(nregs:)
        @all_registers = (1 << nregs) - 1
      end

      def effect_for(instruction)
        case instruction.opcode.name
        when "MOVE"
          effect(
            uses: register(instruction.b),
            defs: register(instruction.a),
            register_assignment_only: true
          )
        when *LOAD_NAMES, "LOADSELF"
          effect(
            uses: NONE,
            defs: register(instruction.a),
            register_assignment_only: true
          )
        when *USE_A_NAMES
          effect(uses: register(instruction.a), defs: NONE)
        when "RETSELF"
          effect(uses: register(0), defs: NONE)
        when *NO_REGISTER_NAMES
          effect(uses: NONE, defs: NONE)
        else
          effect(uses: @all_registers, defs: NONE)
        end
      end

      private

      def register(index) = 1 << index

      def effect(uses:, defs:, register_assignment_only: false)
        Effect.new(uses:, defs:, register_assignment_only:)
      end
    end
  end
end
