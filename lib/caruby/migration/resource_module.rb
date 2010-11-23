require 'caruby/domain/resource_module'

module CaRuby
  module ResourceModule
    # Declares the given classes which will be dynamically modified for migration.
    # The Java caBIG classes are auto-loaded and wrapped as a CaRuby::Resource, if necessary, and enhanced in the migration shim.
    def shims(*classes)
      # nothing to do, since all this method does is ensure that the arguments are auto-loaded when they are referenced
    end
  end
end
