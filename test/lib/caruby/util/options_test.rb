$:.unshift 'lib'

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

  def test_merge
    assert(Options.merge(nil, :create)[:create], "Option not merged into nil options")
    assert_equal(:a, Options.merge(:create, :optional => :a)[:optional], "Option not merged into symbol options")
    assert_equal([:b, :c], Options.merge({:required => [:b]}, :required => [:c])[:required], "Option not merged into hash options")
  end
end