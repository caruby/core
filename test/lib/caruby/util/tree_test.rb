require File.dirname(__FILE__) + '/../../helper'
require "test/unit"
require 'caruby/util/tree'

class TreeTest < Test::Unit::TestCase
  def test_tree
    a = Tree.new(:a)
    assert_equal(a.root, :a, "Tree root incorrect")
    a << :b
    b = a[:b]
    assert_not_nil(b, "Subtree not found")
    assert_equal(b, a.children.first, "Subtree child not found")
    assert_equal(:b, b.root, "Subtree root incorrect")
    assert_nil(a[:b, :c], "Subtree at non-existing path incorrect")
    b << :c
    assert_equal(b[:c], a[:b, :c], "Subtree at path incorrect")
  end

  def test_fill
    assert_equal(Tree.new(:a).fill(:b, :c).root, :c, "Fill result incorrect")
  end
end