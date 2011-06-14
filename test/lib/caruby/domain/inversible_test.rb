$:.unshift 'lib'

require 'caruby'
require "test/unit"

class InversibleTest < Test::Unit::TestCase
  module Domain
    extend CaRuby::Domain
  end
  
  module Resource
    include CaRuby::Resource
    attr_accessor :identifier
  end
  
  class Person; end
  
  class Account
    include Resource
    Domain.add_class(self)
    
    attr_accessor :person
    add_attribute(:person, Person)
  end
  
  class Person
    include Resource
    Domain.add_class(self)
    
    attr_accessor :spouse
    add_attribute(:spouse, Person)
    
    set_attribute_inverse(:spouse, :spouse)
    
    attr_accessor :account
    add_attribute(:account, Account)
    
    set_attribute_inverse(:account, :person)
  end
  
  class Child; end
  
  class Parent
    include Resource
    Domain.add_class(self)
    
    attr_accessor :children
    add_attribute(:children, Child, :collection)
  end
  
  class Child
    include Resource
    Domain.add_class(self)
    
    attr_accessor :parent
    add_attribute(:parent, Parent)
    
    set_attribute_inverse(:parent, :children)
  end

  def test_1_1
    p1 = Person.new
    a1 = Account.new
    p1.account = a1
    assert_same(p1, a1.person, "1:1 inverse not set")
    a2 = Account.new
    p1.account = a2
    assert_same(p1, a2.person, "1:1 inverse not set")
    assert_nil(a1.person, "1:1 previous inverse not cleared")
    p1.account = nil
    assert_nil(a2.person, "1:1 previous inverse not cleared")
  end
  
  def test_1_1_same
    p1 = Person.new
    p2 = Person.new
    p1.spouse = p2
    assert_same(p1, p2.spouse, "1:1 inverse not set")
    p3 = Person.new
    p1.spouse = p3
    assert_same(p3, p1.spouse, "1:1 inverse not set")
    assert_nil(p2.spouse, "1:1 previous inverse not cleared")
    p1.spouse = nil
    assert_nil(p3.spouse, "1:1 previous inverse not cleared")
  end

  def test_1_m
    p1 = Parent.new
    c = Child.new
    c.parent = p1
    assert_same(c, p1.children.first, "1:M inverse not set")
    p2 = Parent.new
    c.parent = p2
    assert_same(c, p2.children.first, "1:M inverse not set")
    assert(p1.children.empty?, "1:M previous inverse not cleared")
    c.parent = nil
    assert(p2.children.empty?, "1:M previous inverse not cleared")
  end
end