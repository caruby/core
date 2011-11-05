require File.dirname(__FILE__) + '/../../helper'
require "test/unit"
require 'caruby/util/domain_extent'

class LazyHastTest < Test::Unit::TestCase

  def test_value_factory
    hash = LazyHash.new { |key| key.to_s }
    assert_equal('1', hash[1], "Factory return value is incorrect")
  end

  def test_default_value_factory
    hash = LazyHash.new
    assert_nil(hash[1], "Default factory does not return")
    assert(hash.has_key?(1), "Default entry not created")
  end

  def test_nil_key
    hash = LazyHash.new
    assert_nil(hash[nil], "nil key does not return")
    assert(!hash.has_key?(nil), "Entry created for nil key")
  end

  def test_reject_missing_value
    hash = LazyHash.new(:compact => true)
    assert(!hash.has_key?(1), "Default entry created for nil value")
  end

  def test_fetch
    assert_raises(IndexError, "Fetch non-existent doesn't raise IndexError") { LazyHash.new.fetch(:a) }
  end
end