require File.dirname(__FILE__) + '/../../helper'
require 'test/unit'
require 'caruby/util/cache'

class CacheTest < Test::Unit::TestCase

  def test_cache
    cache = CaRuby::Cache.new { |n| n % 2 }
    assert_nil(cache[1], "Value mistakenly cached")
    cache.add(1)
    assert_equal(1, cache[1], "Cached value not found")
    assert_nil(cache[2], "Uncached value found")
    assert_equal(1, cache[3], "Cached equivalent not found")
  end

  def test_cache_factory
    cache = CaRuby::Cache.new(Proc.new { |n| n * 4 }) { |n| n % 2 }
    assert_equal(4, cache[1], "Cached factory value not found")
    assert_equal(8, cache[2], "Cached factory value found")
    assert_equal(4, cache[3], "Cached factory equivalent not found")
  end
end