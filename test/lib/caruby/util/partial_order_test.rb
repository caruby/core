require File.dirname(__FILE__) + '/../../helper'
require "test/unit"
require 'caruby/util/partial_order'

class Queued
  include PartialOrder

  attr_reader :queue

  def initialize(on)
    @queue = on.push(self)
  end

  def <=>(other)
    queue.index(self) <=> other.queue.index(other) if queue.equal?(other.queue)
  end
end

class PartialOrderTest < Test::Unit::TestCase
  def test_same_queue
    q = []
    a = Queued.new(q)
    assert_equal(a, a, "Same value, queue not equal")
  end

  def test_different_eql_queue
    a = Queued.new([])
    @b = Queued.new([])
    assert_nil(a <=> @b, "Same value, different queue <=> not nil")
    assert_not_equal(a, @b, "Same value, different queue is equal")
  end

  def test_less_than
    q = []
    a = Queued.new(q)
    b = Queued.new(q)
    c = Queued.new([])
    assert(a < b, "Comparison incorrect")
    assert_nil(a < c, "Comparison incorrect")
  end
end