require File.dirname(__FILE__) + '/../../helper'
require "test/unit"
require 'caruby/util/roman'

class RomanTest < Test::Unit::TestCase
  def test_to_arabic
    ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X' ].each_with_index do |s, n|
      assert_equal(n + 1, s.to_arabic, "Conversion of #{s} incorrect")
    end
  end
  
  def test_to_roman
    ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X' ].each_with_index do |s, n|
      assert_equal(s, (n + 1).to_roman, "Conversion of #{n + 1} incorrect")
    end
  end
end