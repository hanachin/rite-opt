# frozen_string_literal: true

module RiteOpt
  module Rite
    BasicBlock = Data.define(:start_pc, :end_pc) do
      def cover?(pc) = start_pc <= pc && pc < end_pc
      def length = end_pc - start_pc
    end

    Edge = Data.define(:from_pc, :to_pc, :kind)

    CFG = Data.define(:blocks, :edges) do
      def each_reachable_block(start_pc)
        return enum_for(__method__, start_pc) unless block_given?

        blocks_by_pc = blocks.to_h { |block| [block.start_pc, block] }
        edges_by_pc = edges.group_by(&:from_pc)
        visited = {}
        pending = [start_pc]

        until pending.empty?
          pc = pending.pop
          next if visited.key?(pc)

          block = blocks_by_pc[pc]
          next unless block

          visited[pc] = true
          yield block
          edges_by_pc.fetch(pc, []).each { |edge| pending << edge.to_pc }
        end
      end

      def reverse_each_block(&block)
        return enum_for(__method__) unless block

        blocks.reverse_each(&block)
      end
    end

    class CFGBuilder
      def self.build(instructions, catch_handlers:)
        new(instructions, catch_handlers:).build
      end

      def initialize(instructions, catch_handlers:)
        @instructions = instructions
        @catch_handlers = catch_handlers
      end

      def build
        blocks = build_blocks
        CFG.new(blocks:, edges: build_edges(blocks))
      end

      private

      def build_blocks
        leaders = [0, code_end_pc]

        @instructions.each do |instruction|
          leaders << instruction.target_pc if instruction.jump?
          leaders << instruction.next_pc if instruction.terminator?
        end

        @catch_handlers.each do |handler|
          leaders << handler.begin_pos
          leaders << handler.end_pos
          leaders << handler.target
        end

        leaders
          .compact
          .select { |pc| 0 <= pc && pc <= code_end_pc }
          .uniq
          .sort
          .each_cons(2)
          .filter_map do |start_pc, end_pc|
            next if start_pc == end_pc

            BasicBlock.new(start_pc:, end_pc:)
          end
          .freeze
      end

      def build_edges(blocks)
        (normal_edges(blocks) + catch_edges(blocks)).uniq.freeze
      end

      def normal_edges(blocks)
        blocks.flat_map do |block|
          instruction = last_instruction(block)

          if instruction.conditional_jump?
            [
              Edge.new(
                from_pc: block.start_pc,
                to_pc: instruction.target_pc,
                kind: :branch
              ),
              Edge.new(
                from_pc: block.start_pc,
                to_pc: block.end_pc,
                kind: :fallthrough
              )
            ]
          elsif instruction.unwind_jump?
            [
              Edge.new(
                from_pc: block.start_pc,
                to_pc: instruction.target_pc,
                kind: :unwind
              )
            ]
          elsif instruction.jump?
            [
              Edge.new(
                from_pc: block.start_pc,
                to_pc: instruction.target_pc,
                kind: :jump
              )
            ]
          elsif instruction.exit?
            []
          elsif block.end_pc < code_end_pc
            [
              Edge.new(
                from_pc: block.start_pc,
                to_pc: block.end_pc,
                kind: :fallthrough
              )
            ]
          else
            []
          end
        end
      end

      def catch_edges(blocks)
        @catch_handlers.flat_map do |handler|
          blocks.filter_map do |block|
            next unless handler.begin_pos <= block.start_pc
            next unless block.start_pc < handler.end_pos

            Edge.new(
              from_pc: block.start_pc,
              to_pc: handler.target,
              kind: :exception
            )
          end
        end
      end

      def last_instruction(block)
        @instructions.reverse_each.find { |instruction| block.cover?(instruction.pc) }
      end

      def code_end_pc
        @instructions.last&.next_pc || 0
      end
    end
  end
end
