require 'test/lib/caruby/migration/test_case'
require 'examples/clinical_trials/lib/clinical_trials'

# Tests the ClinicalTrials example migration.
module ClinicalTrials
  module MigrationTestCase
    include CaRuby::MigrationTestCase
    
    def setup
      super(FIXTURES)
    end
    
    # Adds the +:target+, +:mapping+ and +:shims+ to the options and delegates
    # to the superclass.
    #
    # @see {CaTissue::MigrationTestCase#create_migrator}
    def create_migrator(fixture, opts={})
      opts[:mapping] ||= File.join(CONFIGS, "#{fixture}_fields.yaml")
      shims = File.join(SHIMS, "#{fixture}_shims.rb")
      if File.exists?(shims) then
        sopt = opts[:shims] ||= []
        sopt << shims
      end
      super
    end
    
    private
    
    # The migration input data directory.
    FIXTURES = 'examples/clinical_trials/data'
  
    # The migration input shim directory.
    SHIMS = 'examples/clinical_trials/lib/clinical_trials/migration'
    
    # The migration configuration directory.
    CONFIGS = 'examples/clinical_trials/conf/migration'
  end
end
