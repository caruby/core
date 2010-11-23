$:.unshift 'lib'

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

  def test_hierarchy
    root= Node.new('root'); a = Node.new('a', root); b = Node.new('b', a); c = Node.new('c', a); d = Node.new('d', c); e = Node.new('e', root)
    expected = [root, a, b, c, d, e].to_set
    closure = root.transitive_closure(:children)
    assert_equal(expected, closure.to_set, "Hierarchy closure incorrect")
    closure.each_with_index { |node, index| closure[index..-1].each { |other| assert(!other.children.include?(node), "Order incorrect") } }
    closure.reject { |node| node.parent.nil? }.each_with_index { |node, index| assert(closure[0..index].detect { |other| other.children.include?(node) }, "Order incorrect") }
  end

  def test_internal
    root= Node.new('root'); a = Node.new('a', root); b = Node.new('b', a); c = Node.new('c', a); d = Node.new('d', c); e = Node.new('e', root)
    expected = [a, b, c, d].to_set
    closure = a.transitive_closure(:children)
    assert_equal(expected, closure.to_set, "Hierarchy closure incorrect")
  end

  def test_leaf
    leaf = Node.new(1)
    assert_equal([leaf], leaf.transitive_closure(:children), "Leaf closure incorrect")
  end

  def test_collection
    a = Node.new('a'); b = Node.new('b'); c = Node.new('c', a); d = Node.new('d', b); e = Node.new('e', c)
    expected = [a, b, c, d, e].to_set
    closure = [a, b].transitive_closure(:children)
    assert_equal(expected, closure.to_set, "Hierarchy closure incorrect")
  end

  def test_cycle
    root= Node.new('root'); a = Node.new('a', root); b = Node.new('b', a); c = Node.new('c', a); c.children << root
    expected = [root, a, b, c].to_set
    assert_equal(expected, a.transitive_closure(:children).to_set, "Cycle closure incorrect")
  end
end