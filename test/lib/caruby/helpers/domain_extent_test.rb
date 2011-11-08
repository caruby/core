require File.dirname(__FILE__) + '/../../helper'
require 'test/unit'
require 'caruby/helpers/domain_extent'

class DomainExtentTest < Test::Unit::TestCase
  # Test composite key class
  class Composite
    attr_reader :a, :b, :c

    def initialize(a, b, c=3)
      super()
      @a = a; @b = b; @c = c
    end

    def ==(other)
      a == other.a && b == other.b && c == other.c
    end
  end

  attr_reader :extent

  def setup
    @extent = DomainExtent.new
  end

  def test_create_on_demand
    assert(!extent.has_key?(String), 'New domain extent not empty')
    assert_not_nil(extent[String], 'Entry not created on demand')
  end

  def test_existing_fetch
    expected = extent[String][1] = 'a'
    target = extent.get(String, 1)
    assert_equal(expected, target, 'Existing entry not found')
  end

  def test_missing_fetch
    assert_nil(DomainExtent.new.get(Symbol, :a), 'Default factory instance not nil')
  end

  def test_simple_key_factory
    extent = DomainExtent.new
    # the String extent key is a number
    # the String extent value is the number as a string
    extent.set_factory(String) { |key| key.to_s }
    assert_equal('1', extent.get(String, 1), 'Simple key instance not found')
  end

  def test_composite_key_factory
    extent = DomainExtent.new
    # the String extent key is a number
    # the String extent value is the number as a string
    extent.set_factory(Composite) { |key| Composite.new(key[:a], key[:b], key[:c]) }
    key = {:a => 1, :b => 2, :c => 3}
    expected = Composite.new(1, 2, 3)
    assert_equal(expected, extent.get(Composite, key), 'Composite key instance not found')
  end
end