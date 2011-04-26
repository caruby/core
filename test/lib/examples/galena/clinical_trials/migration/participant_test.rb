require File.join(File.dirname(__FILE__), 'test_case')

# Tests the ClinicalTrials example migration.
module Galena
  module ClinicalTrials
    class ParticipantMigrationTest < Test::Unit::TestCase
      include MigrationTestCase
      
      def test_target
        verify_target(:participant, :target => ClinicalTrials::Participant) do |pnt|
          assert_not_nil(pnt.ssn, "Missing SSN")
        end
      end
      
      def test_filter
        verify_target(:participant, :target => ClinicalTrials::Participant, :input => FILTER_DATA, :shims => [FILTER_SHIMS]) do |pnt|
          assert_not_nil(pnt.ssn, "Missing SSN")
        end
      end
      
      private
      
      FILTER_DATA = 'examples/galena/data/filter.csv'
      
      FILTER_SHIMS = 'examples/galena/lib/galena/migration/filter_shims.rb'
    end
  end
end
