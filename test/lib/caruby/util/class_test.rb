$:.unshift 'lib'

require "test/unit"
require 'caruby/util/class'

class ClassTest < Test::Unit::TestCase
  def ssn
    '555-55-555'
  end

  def self.redefine_ssn
    redefine_method(:ssn) { |old_method| lambda { send(old_method).delete('-').to_i } }
  end

  def test_redefine_method
    self.class.redefine_ssn
    assert_equal(55555555, ssn, "Method not redefined correctly")
  end

  def test_class_hierarchy
    assert_equal([Array, Object], Array.class_hierarchy.to_a, "Class ancestors incorrect")
  end

  class Person
    attr_reader :social_security_number
    attr_accessor :postal_code
    define_attribute_alias(:ssn, :social_security_number)
    define_attribute_alias(:zip_code, :postal_code)
  end

  def test_attribute_alias
    assert(Person.method_defined?(:ssn), "Reader alias not defined")
    assert(!Person.method_defined?(:ssn=), "Writer alias incorrectly defined")
    assert(Person.method_defined?(:zip_code), "Reader alias not defined")
    assert(Person.method_defined?(:zip_code=), "Writer alias not defined")
  end

  class A; end
  class B < A; end

  def test_range
    assert_equal([B, A, Object],  (B..Object).to_a, "Class range incorrect")
  end

  class OneBased
    attr_accessor :index
    offset_attr_accessor :zero_based_index => :index
    offset_attr_accessor({:two_based_index => :index}, 1)
  end

  def test_offset_attr_accessor
    x = OneBased.new
    x.index = 1
    assert_equal(0, x.zero_based_index, "Offset reader incorrect")
    x.zero_based_index = 1
    assert_equal(2, x.index, "Offset writer incorrect")
    assert_equal(3, x.two_based_index, "Offset reader incorrect")
    x.two_based_index = 1
    assert_equal(0, x.index, "Offset writer incorrect")
  end
end