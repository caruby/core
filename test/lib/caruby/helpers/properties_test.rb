require File.dirname(__FILE__) + '/../../helper'
require "test/unit"
require 'caruby/helpers/properties'
require 'caruby/helpers/log'

class PropertiesTest < Test::Unit::TestCase
  FIXTURES = File.dirname(__FILE__) + '/../../../fixtures/caruby/util/properties'
  INPUT_FILE = File.join(FIXTURES, 'properties.yaml')
  MERGE_FILE = File.join(FIXTURES, 'merge_properties.yaml')
  MERGE_PROPERTIES = ['short', 'nested']

  def setup
    @props = CaRuby::Properties.new(INPUT_FILE, :merge => MERGE_PROPERTIES)
  end

  def test_short_name
    assert_equal('short', @props['short'], 'Short property incorrect')
  end

  def test_dotted_name
    assert_equal('dot', @props['dot.property'], 'Dotted property incorrect')
  end

  def test_symbol
    assert_equal('short', @props[:short], 'Symbol key lookup incorrect')
  end

  def test_nested
    assert_not_nil(@props['nested'], 'Nested property not found')
    assert_equal('A', @props['nested']['a'], 'Nested property value incorrect')
    assert_equal('B', @props['nested']['b'], 'Nested property value incorrect')
    assert_not_nil(@props['nested']['deep'], 'Nested deep property not found')
    assert_equal('U', @props['nested']['deep']['u'], 'Nested deep property value incorrect')
  end
end