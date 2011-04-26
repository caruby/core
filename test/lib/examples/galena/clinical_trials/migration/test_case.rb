$:.unshift 'examples/clinical_trials/lib'

require 'test/lib/caruby/migration/test_case'
require 'clinical_trials'

# Tests the ClinicalTrials example migration.
module Galena
  module ClinicalTrials
    module MigrationTestCase
      include CaRuby::MigrationTestCase
      
      # The migration input data directory.
      FIXTURES = 'examples/galena/data'
    
      # The migration input data directory.
      SHIMS = 'examples/galena/lib/galena/migration'
      
      # The migration configuration directory.
      CONFIGS = 'examples/galena/conf/migration'
      
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
    end
  end
end
