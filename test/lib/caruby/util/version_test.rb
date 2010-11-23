$:.unshift 'lib'

require "test/unit"
require 'caruby/util/version'

class VersionTest < Test::Unit::TestCase
  def test_major
    assert_equal(0, "1".to_version <=> "1".to_version, "Version major comparison incorrect")
    assert_equal(-1, "1".to_version <=> "2".to_version, "Version major comparison incorrect")
    assert_equal(1, "2".to_version <=> "1".to_version, "Version major comparison incorrect")
  end

  def test_minor
    assert_equal(0, "1.1".to_version <=> "1.1".to_version, "Version minor comparison incorrect")
    assert_equal(-1, "1".to_version <=> "1.1".to_version, "Version minor comparison incorrect")
    assert_equal(-1, "1.1".to_version <=> "1.2".to_version, "Version minor comparison incorrect")
    assert_equal(1, "1.2".to_version <=> "1.1".to_version, "Version minor comparison incorrect")
    assert_equal(1, "1.1".to_version <=> "1".to_version, "Version minor comparison incorrect")
  end

  def test_string_components
    assert_equal(0, "1.1alpha".to_version <=> "1.1alpha".to_version, "Version string comparison incorrect")
    assert_equal(1, "1.1alpha".to_version <=> "1.1".to_version, "Version string comparison incorrect")
    assert_equal(-1, "1.1alpha".to_version <=> "1.2".to_version, "Version string comparison incorrect")
  end

  def test_predecessor
    alpha = Version.new(1, '1alpha')
    assert_equal(1, Version.new(1, 1, alpha) <=> alpha, "Version predecessor comparison incorrect")
  end
end