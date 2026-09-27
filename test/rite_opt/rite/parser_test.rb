# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../lib/rite_opt"

class RiteOptRiteParserTest < Minitest::Test
  def test_parses_minimal_rite_binary_losslessly
    source = rite_binary(root: irep_record)
    document = RiteOpt::Rite::Parser.parse(source)

    assert_equal "RITE", document.header.ident
    assert_equal "04", document.header.major_version
    assert_equal "00", document.header.minor_version
    assert_equal source.bytesize, document.header.binary_size
    assert_equal 8, RiteOpt::Rite::Header.binary_size_offset

    assert_equal 1, document.sections.length
    section = document.sections.first
    assert_instance_of RiteOpt::Rite::IrepSection, section
    assert_equal "0400", section.rite_version
    assert_equal 1, section.root.nlocals
    assert_equal 1, section.root.nregs
    assert_equal 0, section.root.rlen
    assert_equal 0, section.root.iseq.ilen
    assert_empty section.root.children

    assert_instance_of RiteOpt::Rite::Footer, document.footer
    assert_equal source, document.source
    assert_equal 0, document.body_tail_span.length
    assert_equal 0, document.trailing_span.length

    assert_equal 0, document.header.span.offset
    assert_equal RiteOpt::Rite::Header.byte_size, document.header.span.length
    assert_equal RiteOpt::Rite::Header.byte_size, section.span.offset
  end

  def test_parses_child_ireps_after_parent_record
    child = irep_record(nlocals: 2, nregs: 3)
    root = irep_record(rlen: 1) + child
    document = RiteOpt::Rite::Parser.parse(rite_binary(root:))

    root_irep = document.sections.first.root
    assert_equal 1, root_irep.rlen
    assert_equal 1, root_irep.children.length
    assert_equal 2, root_irep.children.first.nlocals
    assert_equal 3, root_irep.children.first.nregs
    assert_equal root.bytesize, root_irep.span.length
    assert_equal child.bytesize, root_irep.children.first.span.length
  end

  def test_classifies_known_and_unknown_opaque_sections
    root = irep_record
    irep = "IREP" + [12 + root.bytesize].pack("N") + "0400" + root
    debug = opaque_section("DBG\0", "debug".b)
    lvar = opaque_section("LVAR", "lvar".b)
    unknown = opaque_section("TEST", "raw".b)
    footer = "END\0" + [8].pack("N")
    size = RiteOpt::Rite::Header.byte_size + irep.bytesize + debug.bytesize + lvar.bytesize + unknown.bytesize + footer.bytesize
    document = RiteOpt::Rite::Parser.parse(binary_header(size) + irep + debug + lvar + unknown + footer)

    assert_instance_of RiteOpt::Rite::DebugSection, document.sections[1]
    assert_instance_of RiteOpt::Rite::LvarSection, document.sections[2]
    assert_instance_of RiteOpt::Rite::RawSection, document.sections[3]

    case document.sections[1]
    in RiteOpt::Rite::DebugSection(header: { ident: "DBG\0" })
      # Known section types support direct class patterns.
    else
      flunk "DebugSection did not match directly"
    end
  end

  def test_preserves_bytes_after_declared_binary_size
    binary = rite_binary(root: irep_record)
    source = binary + "extra".b
    document = RiteOpt::Rite::Parser.parse(source)

    assert_equal 5, document.trailing_span.length
    assert_equal "extra".b, document.bytes(document.trailing_span)
  end

  def test_reports_start_offset_of_invalid_section_size
    header_size = RiteOpt::Rite::Header.byte_size
    source = binary_header(header_size + 8) + "TEST" + [7].pack("N")

    error = assert_raises(RiteOpt::Rite::ParseError) do
      RiteOpt::Rite::Parser.parse(source)
    end

    assert_equal header_size + 4, error.offset
  end

  private

  def rite_binary(root:)
    section = "IREP" + [12 + root.bytesize].pack("N") + "0400" + root
    footer = "END\0" + [8].pack("N")
    size = RiteOpt::Rite::Header.byte_size + section.bytesize + footer.bytesize

    binary_header(size) + section + footer
  end

  def binary_header(size)
    "RITE" + "04" + "00" + [size].pack("N") + "MATZ" + "0000"
  end

  def opaque_section(ident, payload)
    ident + [RiteOpt::Rite::SectionHeader.byte_size + payload.bytesize].pack("N") + payload
  end

  def irep_record(nlocals: 1, nregs: 1, rlen: 0)
    body =
      [nlocals, nregs, rlen].pack("n3") +
      [0].pack("n") +
      [0].pack("N") +
      [0].pack("n") +
      [0].pack("n")

    [4 + body.bytesize].pack("N") + body
  end
end
