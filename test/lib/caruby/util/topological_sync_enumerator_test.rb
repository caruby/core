require File.dirname(__FILE__) + '/../../helper'
require "test/unit"
require 'caruby/util/topological_sync_enumerator'

class TopologicalSyncEnumeratorTest < Test::Unit::TestCase
  class Node
    attr_reader :value, :parent
    
    def initialize(value, parent=nil)
      super()
      @value = value
      @parent = parent
    end
    
    def to_s
      value.to_s
    end
    
    alias :inspect :to_s
  end
  
  def test_simple
    a = Node.new(:a)
    b = Node.new(:b)
    c = Node.new(:c, a)
    d = Node.new(:d, b)
    enum = TopologicalSyncEnumerator.new([a, c], [b, d], :parent)
    assert_equal([[a, b], [c, d]], enum.to_a, "Enumeration incorrect")
  end
  
  def test_many
    a = Node.new(:a)
    b = Node.new(:b)
    c1 = Node.new(:c1, a)
    c2 = Node.new(:c2, a)
    d1 = Node.new(:d1, b)
    d2 = Node.new(:d2, b)
    enum = TopologicalSyncEnumerator.new([a, c1, c2], [b, d1, d2], :parent)
    assert_equal([[a, b], [c1, d1], [c2, d2]], enum.to_a, "Enumeration incorrect")
  end
  
  def test_matcher
    a = Node.new(:a)
    b = Node.new(:b)
    c1 = Node.new(:c1, a)
    c2 = Node.new(:c2, a)
    d1 = Node.new(:d1, b)
    d2 = Node.new(:d2, b)
    enum = TopologicalSyncEnumerator.new([a, c1, c2], [b, d1, d2], :parent) { |t, srcs| srcs.last }
    assert_equal([[a, b], [c1, d2], [c2, d1]], enum.to_a, "Enumeration incorrect")
  end
  
  def test_excess_target
    a = Node.new(:a)
    b = Node.new(:b)
    c = Node.new(:c, a)
    enum = TopologicalSyncEnumerator.new([a, c], [b], :parent)
    assert_equal([[a, b]], enum.to_a, "Enumeration incorrect")
  end
  
  def test_excess_source
    a = Node.new(:a)
    b = Node.new(:b)
    d = Node.new(:d, b)
    enum = TopologicalSyncEnumerator.new([a], [b, d], :parent)
    assert_equal([[a, b]], enum.to_a, "Enumeration incorrect")
  end
end