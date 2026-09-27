# frozen_string_literal: true

module RiteOpt
  module Rite
    # Removes semantic NOP instructions from RITE0400 ISEQs.
    #
    # The rewrite compacts instruction bytes and relocates all branch and catch
    # positions. Record, IREP section, and binary sizes are rebuilt from the new
    # byte lengths. LVAR and END sections are position-independent and are kept.
    # DBG is rejected because its PC-to-source mapping also requires rewriting.
    class NopRemoval
      def self.call(source) = new(source).call

      def initialize(source)
        @document = Parser.parse(source.b)
      end

      def call
        ensure_rewrite_supported

        body = +"".b
        @document.sections.each do |section|
          if section in IrepSection
            body << rewrite_irep_section(section)
          else
            body << raw(section.span)
          end
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

      def ensure_rewrite_supported
        irep_found = false

        @document.sections.each do |section|
          case section
          in IrepSection(rite_version: "0400")
            raise UnsupportedRewrite, "RITE must contain one IREP section" if irep_found

            irep_found = true
          in IrepSection
            raise UnsupportedRewrite, "RITE instruction version is not supported"
          in DebugSection
            raise UnsupportedRewrite, "DBG section relocation is not implemented"
          in LvarSection
            next
          in RawSection(header: { ident: })
            raise UnsupportedRewrite, "unsupported RITE section #{ident.inspect}"
          else
            raise UnsupportedRewrite, "unsupported RITE section #{section.class}"
          end
        end

        raise UnsupportedRewrite, "RITE must contain one IREP section" unless irep_found
      end

      def rewrite_irep_section(section)
        payload = section.rite_version.b + rewrite_irep(section.root) + raw(section.tail_span)
        section.header.ident.b + [SectionHeader.byte_size + payload.bytesize].pack("N") + payload
      end

      def rewrite_irep(irep)
        builder = IrepBuilder.new(@document, irep)
        builder.each_irep { |irep_builder| remove_nops(irep_builder) }
        builder.build
      end

      def remove_nops(builder)
        builder.instructions.reject!(&:nop?)
      end

      def raw(span)
        return +"".b unless span

        @document.bytes(span)
      end
    end
  end
end
