require File.dirname(__FILE__) + '/../../helper'
require "test/unit"
require 'caruby/util/collection'
require 'caruby/util/transitive_closure'

class TransitiveClosureTest < Test::Unit::TestCase
  class Node
    attr_reader :parent, :children, :value

    def initialize(value, parent=nil)
      super()
      @value = value
      @parent = parent
      @children = []
      parent.children << self if parent
    end

    def to_s
      value.to_s
    end

    alias :inspect :to_s
  end

  # Verifies closure iteration for the following hierarchy:
  #  root -> a, e
  #  a -> b, c
  #  c -> d
  # The expected iteration is +root+ preceding +a+ and +e+, +a+ preceding +b+ and +c+, +c+ preceding +d+.
  def test_hierarchy
    root= Node.new('root'); a = Node.new('a', root); b = Node.new('b', a); c = Node.new('c', a); d = Node.new('d', c); e = Node.new('e', root)
    verify_closure([root, a, b, c, d, e], root.transitive_closure(:children))
  end

  def test_internal
    root= Node.new('root'); a = Node.new('a', root); b = Node.new('b', a); c = Node.new('c', a); d = Node.new('d', c); e = Node.new('e', root)
    verify_closure([a, b, c, d], a.transitive_closure(:children))
  end

  def test_leaf
    leaf = Node.new(1)
    verify_closure([leaf], leaf.transitive_closure(:children))
  end

  def test_collection
    a = Node.new('a'); b = Node.new('b'); c = Node.new('c', a); d = Node.new('d', b); e = Node.new('e', c)
    verify_closure([a, b, c, d, e], [a, b].transitive_closure(:children))
  end

  def test_cycle
    root= Node.new('root'); a = Node.new('a', root); b = Node.new('b', a); c = Node.new('c', a); c.children << root
    expected = [root, a, b, c].to_set
    verify_closure([root, a, b, c], root.transitive_closure(:children))
  end
  
  def verify_closure(content, closure)
    assert_equal(content.to_set, closure.to_set, "Hierarchy closure incorrect")
    # Verify that no child succeeds the parent.
    closure.each_with_index do |node, index|
      par = node.parent
      if content.include?(par) then
        assert(closure.index(par) < index, "Child #{node} precedes parent #{par}")
      end
    end
  end
end