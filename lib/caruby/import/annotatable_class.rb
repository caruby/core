require 'caruby/util/class'
require 'caruby/util/collection'
require 'caruby/import/annotation_module'

module JavaImport
  # AnnotatableClass adds Annotation modules to an annotation anchor's domain module.
  module AnnotatableClass

    def self.extended(klass)
      klass.class_eval { include CaRuby::Annotatable }
    end

    def annotation_modules
      @annotation_modules ||= []
    end

    # Creates a new AnnotationModule anchored by this class for the given package and database service.
    def create_annotation_module(package, service)
      annotation_modules << AnnotationModule.create_annotation_module(self, package, service)
    end

    # Returns the class with the given unqualified name in one of this AnnotationClass's JavaImport::AnnotationModule
    # modules, or nil if no such class.
    def annotation_class(name)
      annotation_modules.detect_value { |mod| annotation_modules.const_get(name) rescue nil }
    end
  end
end