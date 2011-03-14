$:.unshift 'lib'
$:.unshift '../caruby/lib'

require "test/unit"
require 'caruby'

class JavaTest < Test::Unit::TestCase
  def test_ruby_to_java_date_conversion
    rdt = DateTime.now
    jdt = Java::JavaUtil::Date.from_ruby_date(rdt)
    assert(CaRuby::Resource.value_equal?(rdt, jdt.to_ruby_date), 'Ruby->Java->Ruby date conversion not idempotent')
  end

  def test_java_to_ruby_date_conversion
    cal = Java::JavaUtil::Calendar.instance
    verify_java_to_ruby_date_conversion(cal.time)
    # roll back to a a different DST setting
    if cal.timeZone.useDaylightTime then
      verify_java_to_ruby_date_conversion(flip_DST(cal))
    end
  end
  
  def flip_DST(cal)
    isdt = cal.timeZone.inDaylightTime(cal.time)
    11.times do
      cal.roll(Java::JavaUtil::Calendar::MONTH, false)
      return cal.time if cal.timeZone.inDaylightTime(cal.time) != isdt
    end
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
  
  private 
  
  def verify_java_to_ruby_date_conversion(jdate)
    rdt = jdate.to_ruby_date
    actual = Java::JavaUtil::Date.from_ruby_date(rdt)
    assert_equal(jdate.to_s, actual.to_s, 'Java->Ruby->Java date conversion not idempotent')
    assert_equal(jdate.to_ruby_date, rdt, 'Java->Ruby date reconversion not equal')
  end
end