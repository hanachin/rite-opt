# frozen_string_literal: true

module RiteOpt
  module Rite
    # Removes DBG sections from RITE binaries.
    class DebugRemoval
      def self.call(source) = new(source).call

      def initialize(source)
        @document = Parser.parse(source.b)
      end

      def call
        body = +"".b
        @document.sections.each do |section|
          body << raw(section.span) unless section in DebugSection
        end
        body << raw(@document.footer.span) if @document.footer
        body << raw(@document.body_tail_span)

        binary_size = Header.byte_size + body.bytesize
        header = rewrite_header(binary_size)

        (header << body << raw(@document.trailing_span)).freeze
      end

      private

      def rewrite_header(binary_size)
        header = raw(@document.header.span).dup
        header[Header.binary_size_offset, Header.binary_size_size] = [binary_size].pack("N")
        header
      end

      def raw(span)
        return +"".b unless span

        @document.bytes(span)
      end
    end
  end
end
