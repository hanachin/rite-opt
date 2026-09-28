# frozen_string_literal: true

module RiteOpt
  module Rite
    # Computes live registers at basic-block boundaries.
    #
    # Register sets are Integer bitsets. The analysis walks blocks in reverse
    # ISEQ order for faster convergence, but correctness does not depend on that
    # order. Loops are handled by iterating until no live-in/live-out set changes.
    class Liveness
      NONE = 0

      def self.analyze(cfg:, instructions:, effect_analysis:, exit_live: NONE)
        new(cfg:, instructions:, effect_analysis:, exit_live:).analyze
      end

      def initialize(cfg:, instructions:, effect_analysis:, exit_live: NONE)
        @cfg = cfg
        @effect_analysis = effect_analysis
        @exit_live = exit_live
        @live_in = Hash.new(NONE)
        @live_out = Hash.new(NONE)
        @instructions_by_block = cfg.blocks.to_h do |block|
          [block.start_pc, instructions.select { |instruction| block.cover?(instruction.pc) }]
        end
        @successors_by_block = cfg.edges.group_by(&:from_pc)
      end

      def analyze
        loop do
          changed = false

          @cfg.reverse_each_block do |block|
            live_out = successor_live(block)
            live_in = transfer(block, live_out)

            changed = true if update(@live_out, block.start_pc, live_out)
            changed = true if update(@live_in, block.start_pc, live_in)
          end

          break unless changed
        end

        self
      end

      def live_in(block) = @live_in[block.start_pc]
      def live_out(block) = @live_out[block.start_pc]

      private

      def successor_live(block)
        successors = @successors_by_block.fetch(block.start_pc, [])
        live = successors.reduce(NONE) do |result, edge|
          result | @live_in[edge.to_pc]
        end

        live |= @exit_live unless successors.any? { |edge| edge.kind != :exception }
        live
      end

      def transfer(block, live)
        @instructions_by_block.fetch(block.start_pc).reverse_each do |instruction|
          effect = @effect_analysis.effect_for(instruction)
          live = effect.uses | (live & ~effect.defs)
        end

        live
      end

      def update(values, key, value)
        return false if values[key] == value

        values[key] = value
        true
      end
    end
  end
end
