require 'caruby/util/class'
require 'caruby/util/collection'
require 'caruby/import/importable'
require 'caruby/import/annotation_class'

module JavaImport
  # AnnotationModule creates annotation package modules within a domain module as a context for importing annotation classes.
  module AnnotationModule
    include Importable

    # Creates a new AnnotationModule in the given domain_module from the given annotation package and service.
    def self.create_annotation_module(anchor_class, package, service)
      domain_module = anchor_class.domain_module
      # make parent modules for each package component
      mod = package.split('.').inject(anchor_class.domain_module) do |parent, name|
        mod_id = name.camelize.to_sym
        if parent.const_defined?(mod_id) then
          parent.const_get(mod_id)
        else
          parent.const_set(mod_id, Module.new)
        end
      end
      # the terminal module is the AnnotationModule
      mod.extend(self)
      # initialize the java_package, service and empty access_properties
      mod.module_eval do
        @anchor_class = anchor_class
        @java_package = package
        @service = service
        @resource_module__props = CaRuby::Domain::Properties.new
      end
      mod_name = mod.name[anchor_class.domain_module.name.length..-1]
      logger.debug { "Created annotation module #{mod}." }
      mod
    end

    def java_package
      @java_package
    end

    def service
      @service
    end

    def anchor_class
      @anchor_class
    end

    def access_properties
      @resource_module__props
    end

    # Imports the domain Java class with specified class_name by delegating to Importable and
    # augmenting the importer to include CaRuby::Annotation in each imported class.
    def import_domain_class(class_name)
      anchor_class = @anchor_class
      ann_mod = self
      klass = super(class_name) do
        include CaRuby::Annotation
        @anchor_class = anchor_class
        @annotation_module = ann_mod
        yield if block_given?
      end
      klass.extend(AnnotationClass)
    end
  end
end