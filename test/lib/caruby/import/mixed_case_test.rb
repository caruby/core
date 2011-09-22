# Add the Java jar file to the Java path.
require 'test/fixtures/caruby/import/ext/bin/mixed_case.jar'

require 'java'
require "test/unit"

# Verifies whether JRuby supports a mixed-case package. This can occur in caBIG applications, e.g.
# the +caTissue+ PSBIN custom dynamic extensions. Work-around is to 
class MixedCaseTest < Test::Unit::TestCase
  def test_import
    assert_raises(NameError, "Mixed-case package not resolved") { Java::mixed.Case.Example }
    assert_nothing_raised("Mixed-case JRuby module not resolved") { Java::MixedCase::Example }
  end
end