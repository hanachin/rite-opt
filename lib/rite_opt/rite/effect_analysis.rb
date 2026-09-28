# frozen_string_literal: true

module RiteOpt
  module Rite
    Effect = Data.define(:uses, :defs, :register_assignment_only, :use_operands, :copy, :modeled) do
      def uses?(register) = (uses & (1 << register)) != 0
      def defines?(register) = (defs & (1 << register)) != 0
      def register_assignment_only? = register_assignment_only
      def modeled? = modeled
    end

    # Describes the effects of one instruction that are relevant to analysis.
    #
    # Unknown instructions conservatively read every register and define none.
    # This lets backward liveness analyses start with a small verified opcode set
    # without treating an unmodelled instruction as proof that an earlier value
    # is dead. Forward transformations must also check #modeled? because an
    # unmodelled instruction can still modify registers.
    #
    # use_operands identifies explicit register-reading operands that may be
    # rewritten by transformations such as copy propagation. Implicit reads,
    # such as RETSELF reading R0, are represented only in +uses+. +copy+ names
    # the explicit destination and source operands when the instruction is a
    # register copy.
    class EffectAnalysis
      NONE = 0
      NO_OPERANDS = [].freeze
      USE_A = [:a].freeze
      USE_B = [:b].freeze
      COPY_A_FROM_B = { destination: :a, source: :b }.freeze

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
            use_operands: USE_B,
            register_assignment_only: true,
            copy: COPY_A_FROM_B
          )
        when *LOAD_NAMES, "LOADSELF"
          effect(
            uses: NONE,
            defs: register(instruction.a),
            register_assignment_only: true
          )
        when *USE_A_NAMES
          effect(
            uses: register(instruction.a),
            defs: NONE,
            use_operands: USE_A
          )
        when "RETSELF"
          effect(uses: register(0), defs: NONE)
        when *NO_REGISTER_NAMES
          effect(uses: NONE, defs: NONE)
        else
          effect(uses: @all_registers, defs: NONE, modeled: false)
        end
      end

      private

      def register(index) = 1 << index

      def effect(
        uses:,
        defs:,
        register_assignment_only: false,
        use_operands: NO_OPERANDS,
        copy: nil,
        modeled: true
      )
        Effect.new(uses:, defs:, register_assignment_only:, use_operands:, copy:, modeled:)
      end
    end
  end
end
