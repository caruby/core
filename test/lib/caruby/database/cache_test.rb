require File.dirname(__FILE__) + '/../../helper'
require 'test/unit'
require 'caruby/database/cache'

class CacheTest < Test::Unit::TestCase
  def test_add
    cache = CaRuby::Cache.new { |item| item.identifier }
    a = Item.new(:a)
    assert_nil(cache[a], "Value mistakenly cached")
    cache.add(a)
    assert_equal(a, cache[a], "Cached value not found")
    b = Item.new(:a)
    assert_equal(a, cache[b], "Cached equivalent not found")
    assert_equal(a, cache.add(b), "Cached add replaced existing entry")
  end
  
  def test_add!
    cache = CaRuby::Cache.new { |item| item.identifier }
    a = Item.new(:a)
    cache.add(a)
    b = Item.new(:a)
    cache.add!(b)
    assert_equal(b, cache[a], "Cached add! did not replace existing entry")
  end
  
  def test_clear
    cache = CaRuby::Cache.new { |item| item.identifier }
    a = Item.new(:a)
    cache.add(a)
    cache.clear
    assert_nil(cache[a], "Cache not cleared")
  end
  
  def test_sticky
    cache = CaRuby::Cache.new { |item| item.identifier }
    cache.sticky << Item
    a = Item.new(:a)
    cache.add(a)
    cache.clear
    assert_same(a, cache[a], "Cache sticky entries mistakenly cleared")
  end
  
  private
  
  class Item
    attr_reader :identifier
    
    def initialize(id)
      @identifier = id
    end
  end
end