$:.unshift 'lib'

require "test/unit"
require 'caruby/util/merge'
require 'caruby/util/log'

class MergeTest < Test::Unit::TestCase
  LogCaRuby::Log.instance.open(File.join('test', 'results', 'log', 'caruby.log'), :debug => true)

  class Target
    include Mergeable

    attr_accessor :a, :b, :c, :array

    def self.mergeable_attributes
      [:a, :b]
    end
  end

  class Partial
    attr_accessor :a, :c, :d
  end

  attr_reader :target

  def setup
    @target = Target.new
  end

  def test_merge_attributes_hash
    target.merge_attributes(:a => 1, :b => 2, :c => 3)
    assert_equal(1, target.a, 'Attribute not merged')
    assert_equal(2, target.b, 'Attribute not merged')
    assert_equal(3, target.c, 'Attribute not merged')
  end

  def test_merge_attributes_other
    other = Target.new
    other.a = 1
    other.b = 2
    other.c = 3
    target.merge_attributes(other)
    assert_equal(1, target.a, 'Attribute not merged')
    assert_equal(2, target.b, 'Attribute not merged')
    assert_nil(target.c, 'Non-mergeable attribute merged')
  end

  def test_merge_attributes_other_partial
    other = Partial.new
    other.a = 1
    other.c = 3
    other.d = 4
    target.merge_attributes(other)
    assert_equal(1, target.a, 'Attribute not merged')
    assert_nil(target.c, 'Non-mergeable attribute merged')
  end

  def test_array_merge
    array = [1]
    array.merge([1, 2])
    assert_equal([1, 2], array, 'Array deep merge incorrect')
  end

  def test_array_attribute_merge
    target.a = [1]
    target.merge_attributes(:array => [1, 2])
    assert_equal([1, 2], target.array, 'Array attribute not merged correctly')
  end

  def test_hash_deep_merge
    assert_equal({:a => [1], :b => [2, 3]}, {:a => [1], :b => [2]}.merge({:b => [3]}, :deep), 'Hash deep merge incorrect')
  end

  def test_hash_in_place_deep_merge
    hash = {:a => [1], :b => [2]}
    hash.merge!({:b => [3], :c => 4}, :deep)
    assert_equal({:a => [1], :b => [2, 3], :c => 4}, hash, 'Hash deep merge incorrect')
  end

  def test_nested_hash_deep_merge
    assert_equal({:a => {:b => [1, 2]}, :c => 3}, {:a => {:b => [1]}}.merge({:a => {:b => [2]}, :c => 3}, :deep), 'Hash deep merge incorrect')
  end
end