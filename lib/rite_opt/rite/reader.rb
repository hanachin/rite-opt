# frozen_string_literal: true

module RiteOpt
  module Rite
    class ReadError < StandardError
      attr_reader :offset

      def initialize(message, offset:)
        @offset = offset
        super("#{message} at byte #{offset}")
      end
    end

    Span = Data.define(:offset, :length) do
      def end_offset
        offset + length
      end
    end

    class Reader
      attr_reader :source, :offset, :limit, :last_offset

      def initialize(source, offset: 0, limit: source.bytesize)
        @source = source
        @offset = offset
        @limit = limit
        @last_offset = nil
      end

      def can_read?(length) = length >= 0 && remaining >= length
      def eof? = remaining.zero?
      def read(length) = source.byteslice(take(length).offset, length)
      def take_remaining = take(remaining)

      def take(length)
        @last_offset = offset
        ensure_available(length)

        span = Span.new(offset:, length:)
        @offset += length
        span
      end

      def subreader(length)
        span = take(length)

        self.class.new(
          source,
          offset: span.offset,
          limit: span.end_offset
        )
      end

      def u8
        @last_offset = offset
        ensure_available(1)

        value = source.getbyte(offset)
        @offset += 1
        value
      end

      def u16
        @last_offset = offset
        ensure_available(2)

        value =
          (source.getbyte(offset) << 8) |
          source.getbyte(offset + 1)

        @offset += 2
        value
      end

      def u32
        @last_offset = offset
        ensure_available(4)

        value =
          (source.getbyte(offset) << 24) |
          (source.getbyte(offset + 1) << 16) |
          (source.getbyte(offset + 2) << 8) |
          source.getbyte(offset + 3)

        @offset += 4
        value
      end

      private

      def remaining = limit - offset

      def ensure_available(length)
        return if can_read?(length)

        raise ReadError.new(
          "unexpected end of input",
          offset:
        )
      end
    end
  end
end
