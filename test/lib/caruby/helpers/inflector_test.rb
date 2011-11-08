require File.dirname(__FILE__) + '/../../helper'
require 'test/unit'
require 'caruby/helpers/inflector'

class InflectorTest < Test::Unit::TestCase
   def test_quantified_s
    assert_equal("1 person", "person".quantify(1))
    assert_equal("2 people", "person".quantify(2))
    assert_equal("0 people", "person".quantify(0))
  end
end