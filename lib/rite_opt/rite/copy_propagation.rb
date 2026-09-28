# frozen_string_literal: true

module RiteOpt
  module Rite
    # Propagates register copies inside individual basic blocks.
    #
    # MOVE R2, R1 followed by RETURN R2 can become RETURN R1. The MOVE is left
    # in place so DeadStoreElimination can remove it when it becomes dead.
    #
    # Copy facts never cross a basic-block boundary. An unmodelled instruction
    # is a barrier because it can modify registers not yet represented by
    # EffectAnalysis. Rewrites that would change an instruction's encoded width
    # are skipped so PCs and metadata remain unchanged.
    class CopyPropagation
      def self.call(source) = new(source).call

      def initialize(source)
        @document = Parser.parse(source.b)
      end

      def call
        section = ensure_rewrite_supported
        result = @document.source.dup
        rewrite_irep(result, section.root)
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

      def rewrite_irep(result, irep)
        code = @document.bytes(irep.iseq.code_span).dup
        propagate_copies(code, irep)
        result[irep.iseq.code_span.offset, irep.iseq.code_span.length] = code

        irep.children.each { |child| rewrite_irep(result, child) }
      end

      def propagate_copies(code, irep)
        instructions = InstructionDecoder.decode(code)
        cfg = CFGBuilder.build(instructions, catch_handlers: irep.iseq.catch_handlers)
        analysis = EffectAnalysis.new(nregs: irep.nregs)

        cfg.blocks.each do |block|
          copies = {}

          instructions.each do |instruction|
            next unless block.cover?(instruction.pc)

            effect = analysis.effect_for(instruction)
            unless effect.modeled?
              copies.clear
              next
            end

            rewritten = rewrite_uses(instruction, effect, copies)
            if rewritten != instruction
              code[instruction.source_span.offset, instruction.source_span.length] = rewritten.to_rite
              instruction = rewritten
              effect = analysis.effect_for(instruction)
            end

            source = resolved_copy_source(instruction, effect, copies)
            each_defined_register(effect.defs) { |register| kill_register(copies, register) }
            record_copy(copies, instruction, effect, source)
          end
        end
      end

      def rewrite_uses(instruction, effect, copies)
        effect.use_operands.reduce(instruction) do |current, operand|
          register = current.operand(operand)
          replacement = resolve(copies, register)
          next current if replacement == register

          candidate = current.with_operand(operand, replacement)
          candidate.in_place? ? candidate : current
        end
      end

      def resolved_copy_source(instruction, effect, copies)
        return unless effect.copy

        resolve(copies, instruction.operand(effect.copy.fetch(:source)))
      end

      def record_copy(copies, instruction, effect, source)
        return unless effect.copy

        destination = instruction.operand(effect.copy.fetch(:destination))
        return if destination == source

        copies[destination] = source
      end

      def kill_register(copies, register)
        copies.delete(register)
        copies.delete_if { |_destination, source| source == register }
      end

      def resolve(copies, register)
        while (source = copies[register])
          register = source
        end

        register
      end

      def each_defined_register(defs)
        until defs.zero?
          bit = defs & -defs
          yield bit.bit_length - 1
          defs ^= bit
        end
      end
    end
  end
end
