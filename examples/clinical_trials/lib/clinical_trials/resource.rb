require 'caruby/resource'
require 'caruby/domain/resource_module'

# Example CaRuby::ResourceModule containing some simple domain classes.
module ClinicalTrials
  extend CaRuby::ResourceModule

  # The module included by all ClinicalTrials classes.
  module Resource
    include CaRuby::Resource

    private

    # Adds the given domain class to the ClinicalTrials CaRuby::ResourceModule.
    def self.included(klass)
      ClinicalTrials.add_class(klass)
    end
  end

  private

  # The required include mix-in module.
  @mixin = Resource

  # The required Java package name.
  @java_package = 'clinicaltrials.domain'
  
  # Add the Java jar file to the Java path.
  # For a real application, the jar directories path is set in the application properties file,
  # e.g. ~/.clinicaltrials, which is loaded on demand by {ResourceModule#access_properties}.
  $CLASSPATH << File.join(File.dirname(__FILE__), '..', '..', 'ext', 'bin', 'clinicaltrials.jar')

  # Load the domain class definitions.
  dir = File.join(File.dirname(__FILE__), 'domain')
  load_dir(dir)
end

module JavaLogger
  # Unfortunate caTissue work-around. See CaTissue::Resource.
  # The application might not be caTissue, so allow an unresolved reference.
  Java::EduWustlCommonUtilLogger::Logger.configure("") rescue nil
end
