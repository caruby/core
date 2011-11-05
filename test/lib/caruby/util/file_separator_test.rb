require File.dirname(__FILE__) + '/../../helper'
require 'test/unit'
require 'caruby/util/file_separator'

class FileSeparatorTest < Test::Unit::TestCase
  FIXTURES = File.dirname(__FILE__) + '/../../../fixtures/caruby/util'
  LF_FILE = File.join(FIXTURES, 'lf_line_sep.txt')
  CR_FILE = File.join(FIXTURES, 'cr_line_sep.txt')
  CRLF_FILE = File.join(FIXTURES, 'crlf_line_sep.txt')

  def test_lf_line_separator
    verify_read(LF_FILE, "LF")
  end

  def test_cr_line_separator
    verify_read(CR_FILE, "CR")
  end

  def test_crlf_line_separator
    verify_read(CRLF_FILE, "CRLF")
  end

  def verify_read(file, type)
    lines = File.open(file) { |io| io.readlines }
    assert_equal(3, lines.size, "#{type} line separator not recognized in readlines")
    lines = File.open(file) { |io| io.to_a }
    assert_equal(3, lines.size, "#{type} line separator not recognized in to_a")
  end
end