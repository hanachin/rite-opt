# frozen_string_literal: true

module RiteOpt
  module Rite
    # Replaces dead stores to registers with NOP bytes.
    #
    # Only instructions that are known to have no observable effect other than
    # defining a register are removable. PCs and record sizes remain unchanged;
    # NopRemoval can compact the generated NOPs afterward.
    class DeadStoreElimination
      NONE = 0
      NOP_BYTE = [OPCODES.find(&:nop?).code].pack("C").freeze

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
        eliminate_dead_stores(code, irep)
        result[irep.iseq.code_span.offset, irep.iseq.code_span.length] = code

        irep.children.each { |child| rewrite_irep(result, child) }
      end

      def eliminate_dead_stores(code, irep)
        loop do
          instructions = InstructionDecoder.decode(code)
          cfg = CFGBuilder.build(instructions, catch_handlers: irep.iseq.catch_handlers)
          effect_analysis = EffectAnalysis.new(nregs: irep.nregs)
          liveness = Liveness.analyze(
            cfg:,
            instructions:,
            effect_analysis:,
            exit_live: exit_live(irep)
          )
          changed = false
          each_dead_instruction(cfg, instructions, effect_analysis, liveness) do |instruction|
            replace_with_nops(code, instruction)
            changed = true
          end
          break unless changed
        end
      end

      def each_dead_instruction(cfg, instructions, effect_analysis, liveness)
        cfg.reverse_each_block do |block|
          live = liveness.live_out(block)

          instructions.reverse_each do |instruction|
            next unless block.cover?(instruction.pc)

            effect = effect_analysis.effect_for(instruction)
            if effect.register_assignment_only? && (effect.defs & live) == NONE
              yield instruction
              next
            end

            live = effect.uses | (live & ~effect.defs)
          end
        end
      end

      def replace_with_nops(code, instruction)
        span = instruction.source_span
        code[span.offset, span.length] = NOP_BYTE * span.length
      end

      # A nested IREP can retain values from its outer environment. Until upvar
      # capture is modelled directly, keep every outer register live at exits.
      def exit_live(irep)
        return NONE if irep.children.empty?

        (1 << irep.nregs) - 1
      end
    end
  end
end
