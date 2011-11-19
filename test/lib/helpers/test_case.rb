require File.dirname(__FILE__) + '/../helper'
require 'test/unit'

module CaRuby
  module TestCase
    # Tests the domain object +add_defaults_local+ method.
    # Subclasses are responsible for setting every attribute that is a pre-condition for default value initialization.
    def verify_defaults(subject)
      subject.add_defaults
      msg = "#{subject.qp} with default attributes fails validation"
      assert_nothing_raised(ValidationError, msg) { subject.validate }
    end
  end
end
