# frozen_string_literal: true

module RiteOpt
  module Rite
    class ParseError < StandardError
      attr_reader :offset

      def initialize(message, offset:)
        @offset = offset
        super("#{message} at byte #{offset}")
      end
    end

    Header = Data.define(
      :ident,
      :major_version,
      :minor_version,
      :binary_size,
      :compiler_name,
      :compiler_version,
      :span
    ) do
      def self.ident = "RITE"
      def self.ident_size = 4
      def self.version_size = 2
      def self.binary_size_size = 4
      def self.binary_size_offset = ident_size + version_size * 2
      def self.compiler_name_size = 4
      def self.compiler_version_size = 4

      def self.byte_size =
        ident_size + version_size * 2 + binary_size_size + compiler_name_size + compiler_version_size

      def payload_size = binary_size - self.class.byte_size
    end

    SectionHeader = Data.define(:ident, :size, :span) do
      def self.ident_size = 4
      def self.size_size = 4
      def self.byte_size = ident_size + size_size

      def payload_size = size - self.class.byte_size
    end

    Document = Data.define(
      :source,
      :header,
      :sections,
      :footer,
      :body_tail_span,
      :trailing_span
    ) do
      def bytes(span) = source.byteslice(span.offset, span.length)
      def bytesize = source.bytesize
    end

    IrepSection = Data.define(
      :header,
      :rite_version,
      :root,
      :tail_span,
      :span
    ) do
      def self.ident = "IREP"
      def self.version_size = 4
    end

    DebugSection = Data.define(
      :header,
      :payload_span,
      :span
    ) do
      def self.ident = "DBG\0".b
    end

    LvarSection = Data.define(
      :header,
      :payload_span,
      :span
    ) do
      def self.ident = "LVAR".b
    end

    RawSection = Data.define(
      :header,
      :payload_span,
      :span
    )

    Footer = Data.define(
      :header,
      :payload_span,
      :span
    ) do
      def self.ident = "END\0"
    end

    Irep = Data.define(
      :record_size,
      :nlocals,
      :nregs,
      :rlen,
      :iseq,
      :pool,
      :symbols,
      :children,
      :record_tail_span,
      :span
    ) do
      def self.size_field_size = 4
    end

    Iseq = Data.define(
      :clen,
      :ilen,
      :code_span,
      :catch_handlers,
      :span
    )

    CatchHandler = Data.define(
      :type,
      :begin_pos,
      :end_pos,
      :target,
      :span
    )

    Pool = Data.define(
      :length,
      :entries,
      :span
    )

    PoolEntry = Data.define(
      :type,
      :payload,
      :span
    )

    PoolString = Data.define(
      :length,
      :data_span,
      :terminator_span,
      :span
    )

    PoolInt32 = Data.define(:bits, :span)

    PoolInt64 = Data.define(
      :high_bits,
      :low_bits,
      :span
    )

    PoolFloat = Data.define(:data_span, :span) do
      def self.byte_size = 8
    end

    PoolBigInt = Data.define(
      :length,
      :data_span,
      :span
    )

    Symbols = Data.define(
      :length,
      :entries,
      :span
    )

    SymbolEntry = Data.define(
      :length,
      :name_span,
      :terminator_span,
      :span
    )

    class Parser
      IREP_TT_STR = 0
      IREP_TT_INT32 = 1
      IREP_TT_INT64 = 3
      IREP_TT_FLOAT = 5
      IREP_TT_BIGINT = 7

      NULL_SYMBOL_LENGTH = 0xffff

      def self.parse(source) = new(source).parse

      def initialize(source)
        @source = source
        @reader = Reader.new(source)
        @span_starts = []
      end

      def parse
        header = parse_header
        sections = []
        footer = nil
        body_tail_span = nil

        parse_within(header.payload_size) do
          while @reader.can_read?(SectionHeader.byte_size)
            section = parse_section

            if section.is_a?(Footer)
              footer = section
              break
            end

            sections << section
          end

          body_tail_span = @reader.take_remaining
        end

        Document.new(
          source: @source,
          header:,
          sections:,
          footer:,
          body_tail_span:,
          trailing_span: @reader.take_remaining
        )
      end

      private

      def spanned
        @span_starts << @reader.offset
        yield
      ensure
        @span_starts.pop
      end

      def span
        start = @span_starts.last
        Span.new(offset: start, length: @reader.offset - start)
      end

      def parse_within(size)
        parent = @reader
        @reader = parent.subreader(size)
        yield
      ensure
        @reader = parent
      end

      def parse_header
        spanned do
          ident = @reader.read(Header.ident_size)
          error("not a RITE binary") unless ident == Header.ident

          major_version = @reader.read(Header.version_size)
          minor_version = @reader.read(Header.version_size)

          binary_size = @reader.u32
          error("binary_size is smaller than the header") if binary_size < Header.byte_size
          error("binary_size exceeds input") if binary_size > @source.bytesize

          Header.new(
            ident:,
            major_version:,
            minor_version:,
            binary_size:,
            compiler_name: @reader.read(Header.compiler_name_size),
            compiler_version: @reader.read(Header.compiler_version_size),
            span:
          )
        end
      end

      def parse_section
        spanned do
          header = parse_section_header

          case header.ident
          when IrepSection.ident
            parse_irep_section(header)
          when DebugSection.ident
            parse_opaque_section(DebugSection, header)
          when LvarSection.ident
            parse_opaque_section(LvarSection, header)
          when Footer.ident
            parse_footer(header)
          else
            parse_opaque_section(RawSection, header)
          end
        end
      end

      def parse_section_header
        spanned do
          ident = @reader.read(SectionHeader.ident_size)
          size = @reader.u32
          error("invalid section size") if size < SectionHeader.byte_size

          SectionHeader.new(ident:, size:, span:)
        end
      end

      def parse_irep_section(header)
        error("invalid IREP section size") if header.payload_size < IrepSection.version_size

        parse_within(header.payload_size) do
          IrepSection.new(
            header:,
            rite_version: @reader.read(IrepSection.version_size),
            root: parse_irep,
            tail_span: @reader.take_remaining,
            span:
          )
        end
      end

      def parse_opaque_section(type, header)
        parse_within(header.payload_size) do
          type.new(
            header:,
            payload_span: @reader.take_remaining,
            span:
          )
        end
      end

      def parse_footer(header)
        parse_within(header.payload_size) do
          Footer.new(
            header:,
            payload_span: @reader.take_remaining,
            span:
          )
        end
      end

      def parse_irep
        spanned do
          record_size = @reader.u32
          error("invalid IREP record size") if record_size < Irep.size_field_size

          record = parse_within(record_size - Irep.size_field_size) do
            {
              nlocals: @reader.u16,
              nregs: @reader.u16,
              rlen: @reader.u16,
              iseq: parse_iseq,
              pool: parse_pool,
              symbols: parse_symbols,
              record_tail_span: @reader.take_remaining
            }
          end
          children = Array.new(record[:rlen]) { parse_irep }

          # Child IREPs follow the record and are not part of record_size.
          Irep.new(
            record_size:,
            **record,
            children:,
            span:
          )
        end
      end

      def parse_iseq
        spanned do
          clen = @reader.u16
          ilen = @reader.u32

          Iseq.new(
            clen:,
            ilen:,
            code_span: @reader.take(ilen),
            catch_handlers: Array.new(clen) { parse_catch_handler },
            span:
          )
        end
      end

      def parse_catch_handler
        spanned do
          CatchHandler.new(
            type: @reader.u8,
            begin_pos: @reader.u32,
            end_pos: @reader.u32,
            target: @reader.u32,
            span:
          )
        end
      end

      def parse_pool
        spanned do
          length = @reader.u16

          Pool.new(
            length:,
            entries: Array.new(length) { parse_pool_entry },
            span:
          )
        end
      end

      def parse_pool_entry
        spanned do
          type = @reader.u8

          payload = case type
                    when IREP_TT_STR
                      parse_pool_string
                    when IREP_TT_INT32
                      parse_pool_int32
                    when IREP_TT_INT64
                      parse_pool_int64
                    when IREP_TT_FLOAT
                      parse_pool_float
                    when IREP_TT_BIGINT
                      parse_pool_bigint
                    else
                      error("unknown pool type #{type}")
                    end

          PoolEntry.new(type:, payload:, span:)
        end
      end

      def parse_pool_string
        spanned do
          length = @reader.u16

          PoolString.new(
            length:,
            data_span: @reader.take(length),
            terminator_span: @reader.take(1),
            span:
          )
        end
      end

      def parse_pool_int32
        spanned do
          PoolInt32.new(bits: @reader.u32, span:)
        end
      end

      def parse_pool_int64
        spanned do
          PoolInt64.new(
            high_bits: @reader.u32,
            low_bits: @reader.u32,
            span:
          )
        end
      end

      def parse_pool_float
        spanned do
          PoolFloat.new(
            data_span: @reader.take(PoolFloat.byte_size),
            span:
          )
        end
      end

      def parse_pool_bigint
        spanned do
          length = @reader.u8

          PoolBigInt.new(
            length:,
            data_span: @reader.take(length + 1),
            span:
          )
        end
      end

      def parse_symbols
        spanned do
          length = @reader.u16

          Symbols.new(
            length:,
            entries: Array.new(length) { parse_symbol },
            span:
          )
        end
      end

      def parse_symbol
        spanned do
          length = @reader.u16

          if length == NULL_SYMBOL_LENGTH
            SymbolEntry.new(
              length:,
              name_span: nil,
              terminator_span: nil,
              span:
            )
          else
            SymbolEntry.new(
              length:,
              name_span: @reader.take(length),
              terminator_span: @reader.take(1),
              span:
            )
          end
        end
      end

      def error(message)
        raise ParseError.new(
          message,
          offset: @reader.last_offset
        )
      end
    end
  end
end
