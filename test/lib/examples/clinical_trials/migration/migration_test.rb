require File.dirname(__FILE__) + '/../../../caruby/migration/helpers/test_case'
require 'clinical_trials'

module ClinicalTrials
  # Tests the ClinicalTrials example migration.
  class MigrationTest < Test::Unit::TestCase
    include CaRuby::MigrationTestCase
    
    def setup
      super(DATA)
    end
    
    def test_subject
      assert_nothing_raised(CaRuby::ValidationError, "Missing SSN") do
        verify_target(:subject, SUBJECT_OPTS)
      end
    end

    def test_ssn_filter
     assert_nothing_raised(CaRuby::ValidationError, "Missing SSN") do
       verify_target(:ssn_filter, SSN_FILTER_OPTS)
     end
    end
    
    # Verifies Bug #12.
    def test_blank_name
      migrate(:blank_name, BLANK_NAME_OPTS) do |sbj|
        assert_nil(sbj.name, "#{sbj} blank name was not filtered out")
      end
    end

    def test_bad
      migrate(:bad, BAD_OPTS) do |sbj|
        fail("Bad record #{sbj} was not flagged as an invalid migration")
      end
      assert_equal(1, File.open(BAD).to_a.size, "Bad record not placed in reject file #{BAD}")
    end

    def test_activity_filter
      verify_target(:activity_filter, ACTIVITY_FILTER_OPTS) do |std|
        expected = std.name.split(' ').first
        assert_equal(expected, std.activity_status, "Incorrect activity status")
      end
    end
    
    private

    EXAMPLE = File.dirname(__FILE__) + '/../../../../../examples/clinical_trials/migration'
    
    # The migration input data directory.
    DATA = EXAMPLE + '/data'
    
    # The migration fixture data directory.
    FIXTURES = File.dirname(__FILE__) + '/../../../../fixtures/migration/data'
    
    # The migration input shim directory.
    SHIMS = EXAMPLE + '/lib'
    
    # The migration configuration directory.
    CONFIGS = EXAMPLE + '/conf'
    
    # The migration test results directory.
    RESULTS = File.dirname(__FILE__) + '/../../../../results/clinical_trials'
    
    # The migration bad file.
    BAD = File.expand_path('bad.csv', RESULTS)
    
    # The subject input file.
    SUBJECT_MAPPING = File.expand_path('subject_fields.yaml', CONFIGS)
    
    # The study input file.
    STUDY_MAPPING = File.expand_path('study_fields.yaml', CONFIGS)
    
    # The study default values.
    STUDY_DEFAULTS = File.expand_path('study_defaults.yaml', CONFIGS)
    
    # The study default values.
    STUDY_FILTERS = File.expand_path('study_filters.yaml', CONFIGS)
    
    # The filter shims file.
    SSN_SHIMS = File.expand_path('ssn.rb', SHIMS)

    # The subject migration options.
    SUBJECT_OPTS = {:target => ClinicalTrials::Subject, :mapping => SUBJECT_MAPPING}
    
    # The SSN filter migration options.
    SSN_FILTER_OPTS = {
      :target => ClinicalTrials::Subject,
      :mapping => SUBJECT_MAPPING,
      :shims => SSN_SHIMS
    }
    
    # The activity filter migration options.
    ACTIVITY_FILTER_OPTS = {
      :target => ClinicalTrials::Study,
      :mapping => STUDY_MAPPING,
      :defaults => STUDY_DEFAULTS,
      :filters => STUDY_FILTERS
    }
    
    # The bland name migration options.
    BLANK_NAME_OPTS = {
      :input => File.expand_path('blank_name.csv', FIXTURES),
      :target => ClinicalTrials::Subject,
      :mapping => SUBJECT_MAPPING
    }
    
    # The bad migration options.
    BAD_OPTS = {
      :target => ClinicalTrials::Subject,
      :mapping => SUBJECT_MAPPING,
      :bad => BAD,
      :shims => SSN_SHIMS
    }
  end
end
