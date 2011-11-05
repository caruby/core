require File.dirname(__FILE__) + '/../../helper'
require "test/unit"
require 'caruby/util/options'

class OptionsTest < Test::Unit::TestCase
  def test_present
    assert(Options.get(:key, {:key => true}), "Option true value not returned")
    assert(!Options.get(:key, {:key => false}), "Option true value not returned")
  end

  def test_nil_value
    assert_equal(:a, Options.get(:key, {:key => nil}, :a), "Options nil value not returned")
  end

  def test_false_with_true_default
    assert_equal(false, Options.get(:key, {:key => false}, true), "Option false value with true default doesn't return false")
  end

  def test_missing
    assert_nil(Options.get(:key, {}), "Missing option incorrectly found")
  end

  def test_default_value
    assert_equal(:a, Options.get(:key, {}, :a), "Option default value not used")
  end

  def test_default_block
    assert_equal(:b, Options.get(:key, {}) { :b }, "Option default block not called")
  end

  def test_symbol
    assert(Options.get(:key, :key), "Option not found in singleton options")
  end

  def test_array
    assert(Options.get(:b, [:a, :b]), "Option not found in array options")
  end

  def test_collection_value
    assert_equal([:a], Options.get(:key, {:key => [:a]}, []), "Option array value not returned")
  end
  
  def test_empty_to_hash
    assert_equal({}, Options.to_hash(), "Option to_hash with empty argument list not an empty hash")
  end
  
  def test_nil_to_hash
    assert_equal({}, Options.to_hash(nil), "Option to_hash with nil argument list not an empty hash")
  end
  
  def test_hash_to_hash
    assert_equal({:a => 1}, Options.to_hash({:a => 1}), "Option to_hash with hash argument list not an empty hash")
  end
  
  def test_lish_to_hash
    assert_equal({:a => 1, :b => true, :c => [2, 3]}, Options.to_hash(:a, 1, :b, :c, 2, 3), "Option to_hash with list argument list incorrect")
  end
end