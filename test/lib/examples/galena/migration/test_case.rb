require 'test/lib/caruby/migration/test_case'

# Tests the ClinicalTrials example migration.
module Galena
  class MigrationTestCase
    include CaRuby::MigrationTestCase
    
    # The migration input data directory.
    FIXTURES = 'examples/galena/data'
    
    def setup
      super(FIXTURES)
    end
    
    def test_target
      verify_target(:participant) do |pnt|
        assert_not_nil(pnt.ssn, "Missing SSN")
      end
    end
  end
end
