$:.unshift 'lib'

require "test/unit"
require 'caruby/util/validation'

class ValidationTest < Test::Unit::TestCase
  include Validation

  def test_validate_type
    assert_nothing_raised(TypeError, 'Valid argument declared invalid') { || validate_type(1 => Integer) }
    assert_raises(ArgumentError, 'Missing argument declared valid') { || validate_type(nil => Integer) }
    assert_raises(TypeError, 'Miscast argument declared valid') { || validate_type('a'=>Integer) }
  end
end