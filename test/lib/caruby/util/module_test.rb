require File.dirname(__FILE__) + '/../../helper'
require "test/unit"
require 'caruby/util/module'

module Outer
  module Middle
    class C; end
  end
end

class ModuleTest < Test::Unit::TestCase
  def test_module_with_name
    assert_equal(Outer::Middle, Outer.module_with_name('Middle'), "Unqualified module incorrect")
    assert_nil(Outer.module_with_name('Zed'), "Missing module incorrectly resolves to non-nil value")
    assert_equal(Outer::Middle::C, Outer.module_with_name('Middle::C'), "Qualified module incorrect")
    assert_equal(Outer, Kernel.module_with_name('Outer'), "Top-level module incorrect")
  end
  
  def test_parent_module
    assert_equal(Outer, Outer::Middle.parent_module, "Middle parent module incorrect")
    assert_equal(Outer::Middle, Outer::Middle::C.parent_module, "Inner parent module incorrect")
    assert_equal(Kernel, Outer.parent_module, "Outer parent module incorrect")
  end
end