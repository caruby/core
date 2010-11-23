$:.unshift 'lib'

require "test/unit"
require 'caruby/util/partial_order'

class Queued
  include PartialOrder

  attr_reader :value, :queue

  def initialize(value, on)
    @value = value
    @queue = on.push(self)
  end

  def <=>(other)
    value <=> other.value if queue.equal?(other.queue)
  end
end

class PartialOrderTest < Test::Unit::TestCase
  def test_same_queue
    @a = Queued.new(1, [])
    assert_equal(@a, @a.dup, "Same value, queue not equal")
  end

  def test_different_eql_queue
    @a = Queued.new(1, [])
    @b = Queued.new(1, [])
    assert_nil(@a <=> @b, "Same value, different queue <=> not nil")
    assert_not_equal(@a, @b, "Same value, different queue is equal")
  end

  def test_less_than
    @a = Queued.new(1, [])
    @b = Queued.new(2, @a.queue)
    @c = Queued.new(2, [])
    assert(@a < @b, "Comparison incorrect")
    assert_nil(@a < @c, "Comparison incorrect")
  end
end