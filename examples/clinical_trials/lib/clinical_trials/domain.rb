require 'caruby/domain'
require 'clinical_trials/resource'

# Example CaRuby::Domain containing some simple domain classes.
module ClinicalTrials
  extend CaRuby::Domain

  private

  # Add the Java jar file to the Java path.
  # For a real application, the jar directories path is set in the application properties file,
  # e.g. ~/.clinicaltrials, which is loaded on demand by {Domain#access_properties}.
  $CLASSPATH << File.join(File.dirname(__FILE__), '..', '..', 'ext', 'bin', 'clinicaltrials.jar')

  # Load the domain class definitions.

  # The required Java package name.
  PKG = 'clinicaltrials.domain'
  
  # The domain class definitions.
  SRC_DIR = File.join(File.dirname(__FILE__), 'domain')

  # Enable the resource metadata aspect.
  CaRuby::Domain.extend_module(self, :mixin => Resource, :package => PKG, :directory => SRC_DIR)
  
#  # JRuby alert - The first imported class constructor call results in infinite loop.
#  # E.g. if Address is the first class loaded, then Address.new results in an infinite loop.
#  # CaRuby::Resource overrides initialize and calls super. This is presumably a JRuby bug,
#  # and is verified to exist in the 1.1.6 and the 1.5.3 releases.
#  #
#  # The work-around is to ensure that the first class loaded is never constructed. 
#  # Since DomainObject is abstract, that class is loaded first.
#  #
#  # This bug defies isolation, since the JRuby java class constructor is primitive
#  # and opaque. TODO - isolate, report and fix.
#  import_domain_class(:DomainObject)
#  
#  dir = File.join(File.dirname(__FILE__), 'domain')
#  load_dir(dir)
end

