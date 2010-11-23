$:.unshift 'lib'

require "test/unit"
require 'caruby/util/module'

module Outer
  module Middle
    module InnerModule; end
    class InnerClass; end
  end
end

class ModuleTest < Test::Unit::TestCase
  def test_top_level_module_with_name
    assert_equal(Array, Module.module_with_name(nil, 'Array'), "Top level module incorrect")
  end

  def test_module_with_unqualified_name
    assert_equal(Outer::Middle, Outer.module_with_name('Middle'), "Unqualified module incorrect")
  end

  def test_module_with_qualified_name
    assert_equal(Outer::Middle::InnerModule, Outer.module_with_name('Middle::InnerModule'), "Qualified module incorrect")
  end

  def test_class_with_name
    assert_equal(Outer::Middle::InnerClass, Outer.module_with_name('Middle::InnerClass'), "Inner class incorrect")
  end
end