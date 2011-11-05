require File.dirname(__FILE__) + '/../../helper'
require 'test/unit'
require 'caruby/util/controlled_value'
require 'set'

class ControlledValueTest < Test::Unit::TestCase
  def setup
    @parent = CaRuby::ControlledValue.new('parent')
    @c1 = CaRuby::ControlledValue.new('c1', @parent)
    @gc11 = CaRuby::ControlledValue.new('gc11', @c1)
    @gc12 = CaRuby::ControlledValue.new('gc12', @c2)
    @c2 = CaRuby::ControlledValue.new('c2', @parent)
    @gc21 = CaRuby::ControlledValue.new('gc21', @c2)
  end

  def test_parent
    assert_same(@c1, @gc11.parent, "Parent incorrect")
    assert(@c1.children.include?(@gc11), "Children incorrect")
  end

  def test_descendants
    assert(@parent.descendants.include?(@gc21), "Descendants incorrect")
  end
end