# Add the Java jar file to the Java path.
require File.dirname(__FILE__) + '/../../../fixtures/caruby/import/ext/bin/mixed_case.jar'

require 'java'
require "test/unit"

# Verifies whether JRuby supports a mixed-case package. This can occur in caBIG applications, e.g.
# the +caTissue+ PSBIN custom dynamic extensions. Work-around is to import the class as a string.
class MixedCaseTest < Test::Unit::TestCase
  def test_import
    assert_raises(NameError, "Mixed-case package resolved") { Java::mixed.Case.Example }
    assert_raises(NameError, "Mixed-case JRuby module resolved") { Java::MixedCase::Example }
    assert_nothing_raised("Mixed-case import as a string not resolved") {java_import "mixed.Case.Example" }
  end
end