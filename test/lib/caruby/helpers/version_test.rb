require File.dirname(__FILE__) + '/../../helper'
require "test/unit"
require 'caruby/helpers/version'

class VersionTest < Test::Unit::TestCase
  def test_major
    assert_equal(0, Version.parse('1') <=> Version.parse('1'), "Version major comparison incorrect")
    assert_equal(-1, Version.parse('1') <=> Version.parse('2'), "Version major comparison incorrect")
    assert_equal(1, Version.parse('2') <=> Version.parse('1'), "Version major comparison incorrect")
  end

  def test_minor
    assert_equal(0, Version.parse('1.1') <=> Version.parse('1.1'), "Version minor comparison incorrect")
    assert_equal(-1, Version.parse('1') <=> Version.parse('1.1'), "Version minor comparison incorrect")
    assert_equal(-1, Version.parse('1.1') <=> Version.parse('1.2'), "Version minor comparison incorrect")
    assert_equal(1, Version.parse('1.2') <=> Version.parse('1.1'), "Version minor comparison incorrect")
    assert_equal(1, Version.parse('1.1') <=> Version.parse('1'), "Version minor comparison incorrect")
  end

  def test_string_components
    assert_equal(0, Version.parse('1.1alpha') <=> Version.parse('1.1alpha'), "Version string comparison incorrect")
    assert_equal(1, Version.parse('1.1alpha') <=> Version.parse('1.1'), "Version string comparison incorrect")
    assert_equal(-1, Version.parse('1.1alpha') <=> Version.parse('1.2'), "Version string comparison incorrect")
  end

  def test_predecessor
    alpha = Version.new(1, '1alpha')
    assert_equal(1, Version.new(1, 1, alpha) <=> alpha, "Version predecessor comparison incorrect")
  end
end