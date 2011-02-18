$:.unshift 'lib'

require 'generator'
require "test/unit"
require 'caruby/util/collection'
require 'caruby/util/visitor'

class Node
  attr_reader :parent, :children, :friends

  attr_accessor :value

  def initialize(value, parent=nil)
    @value = value
    @children = []
    @friends = []
    @parent = parent
    @parent.children << self if @parent
  end

  def <=>(other)
    value <=> other.value if other
  end

  def to_s
    "#{self.class.name}@#{hash}{value => #{value}}"
  end

  alias :inspect :to_s
end

class VistorTest < Test::Unit::TestCase
  def test_visit
    parent = Node.new(1)
    child = Node.new(2, parent)
    multiplier = 1
    result = CaRuby::Visitor.new { |node| node.children }.visit(parent) { |node| node.value *= (multiplier *= 2) }
    assert_equal(2, parent.value, "Visit parent value incorrect")
    assert_equal(8, child.value, "Visit child value incorrect")
    assert_equal(2, result, "Visit result incorrect")
  end

  def test_cycle
    parent = Node.new(1)
    child = Node.new(2, parent)
    child.children << parent
    multiplier = 2
    CaRuby::Visitor.new { |node| node.children }.visit(parent) { |node| node.value *= multiplier }
    assert_equal(2, parent.value, "Cycle parent value incorrect")
    assert_equal(4, child.value, "Cycle child value incorrect")
  end

  def test_depth_first
    parent = Node.new(1)
    child = Node.new(2, parent)
    multiplier = 1
    CaRuby::Visitor.new(:depth_first) { |node| node.children }.visit(parent) { |node| node.value *= (multiplier *= 2) }
    assert_equal(4, parent.value, "Depth-first parent value incorrect")
    assert_equal(4, child.value, "Depth-first child value incorrect")
  end

  def test_return
    parent = Node.new(1)
    child = Node.new(2, parent)
    result = increment(parent, 2)
    assert_nil(result, "Pre-emptive return incorrect")
    assert_equal(2, parent.value, "Pre-emptive return parent value incorrect")
    assert_equal(2, child.value, "Pre-emptive return child value incorrect")
  end

  def test_visited_detection
    parent = Node.new(1)
    child = Node.new(2, parent)
    c2 = Node.new(3, parent)
    c2.children << child
    result = CaRuby::Visitor.new { |node| node.children }.visit(parent) { |node| node.value += 1 }
    assert_equal(3, child.value, "Child visited twice")
  end

  def test_root_cycle
    parent = Node.new(1)
    c1 = Node.new(2, parent)
    c2 = Node.new(3, parent)
    c2.children << parent
    gc11 = Node.new(4, c1)
    gc12 = Node.new(5, c1)
    gc12.children << c1
    gc121 = Node.new(6, gc12)
    gc121.children << parent
    visitor = CaRuby::Visitor.new { |node| node.children }
    result = visitor.visit(parent)
    assert_equal([[2, 5, 2], [1, 2, 5, 6, 1], [1, 3, 1]], visitor.cycles.map { |cycle| cycle.map { |node| node.value } }, "Root cycles incorrect")
  end

  def increment(parent, limit)
    CaRuby::Visitor.new { |node| node.children }.visit(parent) { |node| node.value < limit ? node.value += 1 : return }
  end

  def test_collection
    p1 = Node.new(1)
    child = Node.new(2, p1)
    p2 = Node.new(3)
    p2.children << child
    result = CaRuby::Visitor.new { |pair| SyncEnumerator.new(pair.first.children, pair.last.children).to_a }.to_enum([p1, p2]).map { |pair| [pair.first.value, pair.last.value] }
    assert_equal([[1, 3], [2, 2]], result.to_a, "Collection visit result incorrect")
  end

  def node_value(node)
    node.value if node
  end

  def test_enumeration
    parent = Node.new(1)
    c1 = Node.new(2, parent)
    c2 = Node.new(3, parent)
    result = CaRuby::Visitor.new { |node| node.children }.to_enum(parent).map { |node| node.value }
    assert_equal([1, 2, 3], result, "Enumeration result incorrect")
  end

  def test_exclude_cycles
    parent = Node.new(1)
    c1 = Node.new(2, parent)
    gc11 = Node.new(3, c1)
    gc11.children << c1
    c2 = Node.new(4, parent)
    gc21 = Node.new(5, c2)
    gc21.children << parent
    result = CaRuby::Visitor.new(:prune_cycle) { |node| node.children }.to_enum(parent).map { |node| node.value }
    assert_equal([1, 2, 3], result, "Exclude result incorrect")
  end

  def test_missing_block
    parent = Node.new(1)
    c1 = Node.new(2, parent)
    c2 = Node.new(3, parent)
    visitor = CaRuby::Visitor.new { |node| node.children }
    visitor.visit(parent)
    assert_equal([parent, c1, c2], visitor.visited.values.sort, "Missing visit operator result incorrect")
  end

  def test_filter
    parent = Node.new(1)
    c1 = Node.new(2, parent)
    c2 = Node.new(3, parent)
    gc1 = Node.new(4, c1)
    gc2 = Node.new(5, c1)
    visitor = CaRuby::Visitor.new { |node| node.children }.filter { |parent, children| children.first if parent.value < 4 }
    result = visitor.to_enum(parent).map { |node| node.value }
    assert_equal([1, 2, 4], result, "Filter result incorrect")
  end

  def test_sync_without_block
    p1 = Node.new(1)
    c11 = Node.new(2, p1)
    c12 = Node.new(3, p1)
    gc111 = Node.new(4, c11)
    gc121 = Node.new(5, c12)
    p2 = Node.new(6)
    c21 = Node.new(7, p2)
    c22 = Node.new(8, p2)
    gc211 = Node.new(9, c21)
    visitor = CaRuby::Visitor.new { |node| node.children }.sync
    result = visitor.to_enum(p1, p2).map { |pair| pair.map { |node| node.value unless node.nil? } }
    assert_equal([[1, 6], [2, 7], [4, 9], [3, 8], [5, nil]], result, "Sync without block result incorrect")
  end

  def test_sync_with_matcher
    p1 = Node.new(1)
    c11 = Node.new(2, p1)
    c12 = Node.new(3, p1)
    gc111 = Node.new(4, c11)
    gc121 = Node.new(5, c12)
    p2 = Node.new(1)
    c21 = Node.new(2, p2)
    c22 = Node.new(3, p2)
    gc211 = Node.new(5, c21)
    visitor = CaRuby::Visitor.new { |node| node.children }
    synced = visitor.sync { |nodes, others| nodes.to_compact_hash { |n| others.detect { |o| n.value == o.value } } }
    result = synced.to_enum(p1, p2).map { |pair| pair.map { |node| node.value if node } }
    assert_equal([[1, 1], [2, 2], [4, nil], [3, 3], [5, nil]], result, "Sync with block result incorrect")
  end

  def test_sync_noncollection
    p1 = Node.new(1)
    child = Node.new(2, p1)
    p2 = Node.new(3)
    p2.children << child
    visitor = CaRuby::Visitor.new { |node| node.children.first }.sync
    value_hash = {}
    result = visitor.visit(p1, p2) { |first, last| value_hash[node_value(first)] = node_value(last) }
    assert_equal({1 => 3, 2 => 2}, value_hash, "Sync with non-collection children result incorrect")
    result = visitor.to_enum(p1, p2).map { |first, last| [node_value(first), node_value(last)] }
    assert_equal([[1, 3], [2, 2]], result.to_a, "Sync with non-collection children result incorrect")
  end

  def test_sync_missing
    p1 = Node.new(1)
    p2 = Node.new(2)
    c1 = Node.new(3, p1)
    c2 = Node.new(4, p2)
    gcren = Node.new(5, c2)
    visitor = CaRuby::Visitor.new { |node| node.children.first }.sync
    result = visitor.to_enum(p1, p2).map { |pair| [node_value(pair.first), node_value(pair.last)] }
    assert_equal([[1, 2], [3, 4]], result.to_a, "Sync with missing children result incorrect")
  end

  def test_missing_node
    parent = Node.new(1)
    child = Node.new(2, parent)
    multiplier = 2
    CaRuby::Visitor.new { |node| node.children unless node == child }.visit(parent) { |node| node.value *= multiplier }
    assert_equal(2, parent.value, "Missing node parent value incorrect")
    assert_equal(4, child.value, "Missing node child value incorrect")
  end

  def test_noncollection_traversal
    parent = Node.new(1)
    child = Node.new(2, parent)
    multiplier = 2
    CaRuby::Visitor.new { |node| node.parent }.visit(child) { |node| node.value *= multiplier }
    assert_equal(2, parent.value, "Non-collection parent value incorrect")
    assert_equal(4, child.value, "Non-collection child value incorrect")
  end

  def test_parent
    parent = Node.new(1)
    c1 = Node.new(2, parent)
    c2 = Node.new(3, parent)
    gc = Node.new(4, c1)
    visitor = CaRuby::Visitor.new { |node| node.children }
    visitor.visit(parent) { |node| node.value = visitor.parent.nil? ? 0 : visitor.parent.value + 1 }
    assert_equal(0, parent.value, "Parent value incorrect")
    assert_equal(1, c1.value, "Child value incorrect")
    assert_equal(1, c2.value, "Child value incorrect")
    assert_equal(2, gc.value, "gc value incorrect")
  end

  def test_parent_depth_first
    # An interesting variant: the parent node value is not reset until after the children are visited
    parent = Node.new(1)
    c1 = Node.new(2, parent)
    c2 = Node.new(3, parent)
    gc = Node.new(4, c1)
    visitor = CaRuby::Visitor.new(:depth_first) { |node| node.children }
    visitor.visit(parent) { |node| node.value = visitor.parent.nil? ? 0 : visitor.parent.value + 1 }
    assert_equal(0, parent.value, "Parent value incorrect")
    assert_equal(2, c1.value, "Child value incorrect")
    assert_equal(2, c2.value, "Child value incorrect")
    assert_equal(3, gc.value, "gc value incorrect")
  end

  def test_visited
    parent = Node.new(1)
    c1 = Node.new(nil, parent)
    c2 = Node.new(nil, parent)
    gc = Node.new(nil, c1)
    visitor = CaRuby::Visitor.new { |node| node.children }
    visitor.visit(parent) { |node| node.value ||= visitor.visited[node.parent] + 1 }
    assert_equal(1, parent.value, "Parent value incorrect")
    assert_equal(2, c1.value, "Child value incorrect")
    assert_equal(2, c2.value, "Child value incorrect")
    assert_equal(3, gc.value, "gc value incorrect")
  end

  def test_visited_result
    parent = Node.new(1)
    c1 = Node.new(2, parent)
    c2 = Node.new(3, parent)
    gc = Node.new(4, c1)
    visitor = CaRuby::Visitor.new { |node| node.children }
    visitor.visit(parent) { |node| node.value + 1 }
    assert_equal(2, visitor.visited[parent], "Parent visited value incorrect")
    assert_equal(3, visitor.visited[c1], "Child visited value incorrect")
    assert_equal(4, visitor.visited[c2], "Child visited value incorrect")
    assert_equal(5, visitor.visited[gc], "gc visited value incorrect")
  end
end