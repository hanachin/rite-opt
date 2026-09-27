# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/rite_opt/rite/reader"
require_relative "../lib/rite_opt/rite/parser"
require_relative "../lib/rite_opt/rite/lvar_removal"

class LvarRemovalTest < Minitest::Test
  def test_removes_lvar_section_and_updates_binary_size
    debug = section("DBG\0".b, "debug-data")
    lvar = section("LVAR".b, "lvar-data")
    input = rite(extra_sections: [debug, lvar])

    result = RiteOpt::Rite::LvarRemoval.call(input)
    document = RiteOpt::Rite::Parser.parse(result)

    assert_equal [RiteOpt::Rite::IrepSection, RiteOpt::Rite::DebugSection], document.sections.map(&:class)
    assert_equal result.bytesize, document.header.binary_size
    assert_equal input.bytesize - lvar.bytesize, result.bytesize
  end

  def test_is_idempotent
    input = rite(extra_sections: [section("LVAR".b, "lvar-data")])

    first = RiteOpt::Rite::LvarRemoval.call(input)
    second = RiteOpt::Rite::LvarRemoval.call(first)

    assert_equal first, second
  end

  def test_preserves_trailing_bytes
    trailing = "TRAILING".b
    input = rite(extra_sections: [section("LVAR".b, "lvar-data")]) + trailing

    result = RiteOpt::Rite::LvarRemoval.call(input)
    document = RiteOpt::Rite::Parser.parse(result)

    assert_equal trailing, document.bytes(document.trailing_span)
    assert_equal result.bytesize - trailing.bytesize, document.header.binary_size
  end

  private

  def rite(extra_sections: [])
    irep = section("IREP", "0400" + irep_record)
    footer = section("END\0".b, "")
    body = irep + extra_sections.join + footer
    "RITE0400" + [20 + body.bytesize].pack("N") + "MATZ0000" + body
  end

  def irep_record
    code = [118].pack("C*")
    iseq = [0].pack("n") + [code.bytesize].pack("N") + code
    pool_and_symbols = [0, 0].pack("nn")
    record_size = 10 + iseq.bytesize + pool_and_symbols.bytesize
    [record_size, 1, 1, 0].pack("Nnnn") + iseq + pool_and_symbols
  end

  def section(ident, payload)
    ident + [8 + payload.bytesize].pack("N") + payload
  end
end
