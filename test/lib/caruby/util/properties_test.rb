$:.unshift('lib')

require "test/unit"
require 'caruby/util/properties'
require 'caruby/util/log'

class PropertiesTest < Test::Unit::TestCase
  LOG_FILE = File.join('test', 'results', 'log', 'caruby.log')
  FIXTURES_DIR = File.join('test', 'fixtures', 'caruby', 'util', 'properties')
  INPUT_FILE = File.join(FIXTURES_DIR, 'properties.yaml')
  MERGE_FILE = File.join(FIXTURES_DIR, 'merge_properties.yaml')
  MERGE_PROPERTIES = ['short', 'nested']

  def setup
    CaRuby::Log.instance.open(LOG_FILE, :debug => true)
    @properties = CaRuby::Properties.new(INPUT_FILE, :merge => MERGE_PROPERTIES)
  end

  def test_short_name
    assert_equal('short', @properties['short'], 'Short property incorrect')
  end

  def test_dotted_name
    assert_equal('dot', @properties['dot.property'], 'Dotted property incorrect')
  end

  def test_symbol
    assert_equal('short', @properties[:short], 'Symbol key lookup incorrect')
  end

  def test_nested
    assert_not_nil(@properties['nested'], 'Nested property not found')
    assert_equal('A', @properties['nested']['a'], 'Nested property value incorrect')
    assert_equal('B', @properties['nested']['b'], 'Nested property value incorrect')
    assert_not_nil(@properties['nested']['deep'], 'Nested deep property not found')
    assert_equal('U', @properties['nested']['deep']['u'], 'Nested deep property value incorrect')
  end

  def test_merge
    @properties.load_properties_file(MERGE_FILE)
    assert_equal('long', @properties['short'], 'Merge property value not overridden')
    assert_equal('dash', @properties['dot.property'], 'Non-merge property value not overridden')
    assert_not_nil(@properties['nested'], 'Nested property override incorrect')
    assert_equal('X', @properties['nested']['a'], 'Nested property value not overridden')
    assert_equal('B', @properties['nested']['b'], 'Nested property value not retained')
    assert_equal('C', @properties['nested']['c'], 'Nested property value not added')
    assert_equal('U', @properties['nested']['deep']['u'], 'Nested deep property value not retained')
    assert_equal('V', @properties['nested']['deep']['v'], 'Nested deep property value not added')
  end
end