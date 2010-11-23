$:.unshift 'lib'
$:.unshift '../caruby/lib'

require "test/unit"

require 'caruby/import/java'

class JavaTest < Test::Unit::TestCase
  def test_ruby_to_java_date_conversion
    ruby_date = DateTime.now
    java_date = Java::JavaUtil::Date.from_ruby_date(ruby_date)
    actual = java_date.to_ruby_date
    assert_equal(ruby_date.to_s, actual.to_s, 'Date conversion not idempotent')
  end

  def test_java_to_ruby_date_conversion
    java_date = Java::JavaUtil::Calendar.instance.time
    ruby_date = java_date.to_ruby_date
    actual = Java::JavaUtil::Date.from_ruby_date(ruby_date)
    assert_equal(java_date.to_s, actual.to_s, 'Date conversion not idempotent')
  end

  def test_to_ruby
    assert_same(Java::JavaUtil::BitSet, Class.to_ruby(java.util.BitSet.java_class), "Java => Ruby class incorrect")
  end

  def test_list_delete_if
    list = Java::JavaUtil::ArrayList.new << 1 << 2
    assert_same(list, list.delete_if { |n| n == 2 })
    assert_equal([1], list.to_a, "Java ArrayList delete_if incorrect")
  end

  def test_set_delete_if
    list = Java::JavaUtil::HashSet.new << 1 << 2
    assert_same(list, list.delete_if { |n| n == 2 })
    assert_equal([1], list.to_a, "Java HashSet delete_if incorrect")
  end

  def test_list_clear
    list = Java::JavaUtil::ArrayList.new
    assert(list.empty?, "Cleared ArrayList not empty")
    assert_same(list, list.clear, "ArrayList clear result incorrect")
  end

  def test_set_clear
    set = Java::JavaUtil::HashSet.new
    assert(set.empty?, "Cleared HashSet not empty")
    assert_same(set, set.clear, "HashSet clear result incorrect")
  end

  def test_set_merge
    set = Java::JavaUtil::HashSet.new << 1
    other = Java::JavaUtil::HashSet.new << 2
    assert_same(set, set.merge(other), "HashSet merge result incorrect")
    assert(set.include?(2), "HashSet merge not updated")
    assert_same(set, set.clear, "HashSet clear result incorrect")
  end
end