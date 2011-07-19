require 'test/lib/caruby/migration/test_case'
require 'examples/clinical_trials/lib/clinical_trials'

module ClinicalTrials
  # Tests the ClinicalTrials example migration.
  class MigrationTest < Test::Unit::TestCase
    include CaRuby::MigrationTestCase
    
    def setup
      super(FIXTURES)
    end
    
#    def test_subject
#      verify_target(:subject, :target => ClinicalTrials::Subject, :mapping=> SUBJECT_MAPPING) do |sbj|
#        assert_not_nil(sbj.ssn, "Missing SSN")
#      end
#    end
#    
#    def test_ssn_filter
#      verify_target(:ssn_filter, :target => ClinicalTrials::Subject, :mapping=> SUBJECT_MAPPING, :shims => SSN_SHIMS) do |sbj|
#        assert_not_nil(sbj.ssn, "Missing SSN")
#      end
#    end
    
    def test_activity_filter
      verify_target(:activity_filter, :target => ClinicalTrials::Study, :mapping=> STUDY_MAPPING, :defaults => STUDY_DEFAULTS, :filters => STUDY_FILTERS) do |std|
        expected = std.name.split(' ').first
        assert_equal(expected, std.activity_status, "Incorrect activity status")
      end
    end
    
    private
    
    # The migration input data directory.
    FIXTURES = 'examples/clinical_trials/data'
  
    # The migration input shim directory.
    SHIMS = 'examples/clinical_trials/lib/clinical_trials/migration'
    
    # The migration configuration directory.
    CONFIGS = 'examples/clinical_trials/conf/migration'
    
    # The subject input file.
    SUBJECT_MAPPING = File.join(CONFIGS, "subject_fields.yaml")
    
    # The study input file.
    STUDY_MAPPING = File.join(CONFIGS, "study_fields.yaml")
    
    # The study default values.
    STUDY_DEFAULTS = File.join(CONFIGS, "study_defaults.yaml")
    
    # The study default values.
    STUDY_FILTERS = File.join(CONFIGS, "study_filters.yaml")
    
    # The filter shims file.
    SSN_SHIMS = File.join(SHIMS, "ssn_shim.rb")
  end
end
