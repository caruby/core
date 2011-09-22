require 'caruby/domain/metadata'
require 'caruby/resource'

module CaRuby
  module Domain
    # Importer extends a {Module} with Java class import support.
    #
    # A Java class is imported into JRuby on demand by referencing the class name.
    # Import on demand is induced by a reference to the class, e.g., given the
    # following domain resource module definition:
    #   module ClinicalTrials
    #     module Resource
    #      ...
    #     end
    #
    #     CaRuby::Domain.extend_module(self, Resource, 'org.nci.ctms')
    # then the first reference by name to +ClinicalTrials::Subject+
    # imports the Java class +org.nci.ctms.Subject+ into the JRuby class wrapper
    # +ClinicalTrials::Subject+. The +ClinicalTrials::Resource+ module is included
    # in +ClinicalTrials::Subject+ and the Java property meta-data is introspected
    # into {Attributes}.
    module Importer
      # Extends the given module with Java class meta-data import support.
      #
      # @param [Module] mod the module to extend
      # @param [{Symbol => Object}] opts the extension options
      # @option opts (see #configure)
      def self.extend_module(mod, opts)
        mod.extend(self).configure_importer(opts)
      end
  
      # Imports a Java class constant on demand. If the class does not already
      # include this module's mixin, then the mixin is included in the class.
      #
      # @param [Symbol] symbol the missing constant
      # @return [Class] the imported class
      # @raise [NameError] if the symbol is not an importable Java class
      def const_missing(symbol)
        logger.debug { "Detecting whether #{symbol} is a #{@pkg} Java class..." }
        # Append the symbol to the package to make the Java class name.
        begin
          klass = java_import "#{@pkg}.#{symbol}"
          resource_import(klass)
        rescue NameError
          logger.debug { "#{symbol} is not recognized as a #{@pkg} Java class - #{$!}\n#{caller.qp}." }
          super
        end
        logger.info(klass.pp_s)
        klass
      end
      
      # Imports the given Java class and introspects the {Metadata}.
      # The Java class is assumed to be defined in this module's package.
      # This module's mixin is added to the class.
      #
      # @param [Class] class_or_name the source directory
      # @raise [NameError] if the symbol does not correspond to a Java class
      #   in this module's package
      def resource_import(klass)
        # Add the superclass metadata, if necessary.
        sc = klass.superclass
        unless sc < @mixin or klass.parent_module != sc.parent_module then
          const_get(sc.name.demodulize)
        end
        java_import(klass)
        ensure_metadata_introspected(klass)
        klass
      end
      
      # @param [Class, String] class_or_name the class to import into this module
      # @return [Class] the imported class
      def java_import(class_or_name)
        # JRuby 1.4.x does not support a class argument
        begin
          Class === class_or_name ? super(class_or_name.java_class.name) : super
        rescue Exception
          raise JavaImportError.new("#{class_or_name} is not a Java class - #{$!}")
        end
      end

      # Configures this importer with the given options. This method is intended for use by the
      # +extend_module+ method.
      #
      # @param [{Symbol => Object}] opts the extension options
      # @option opts [String] :package the required Java package name
      # @option opts [Module, Proc] :metadata the optional {Metadata} extension module or proc (default {Metadata})
      # @option opts [Module] :mixin the optional mix-in module (default {Resource})
      # @option opts [String] :directory the optional directory of source class definitions to load
      def configure_importer(opts)
        @pkg = opts[:package]
        if @pkg.nil? then raise ArgumentError.new("Required domain package option not found") end
        @metadata = opts[:metadata] || Metadata
        @mixin = opts[:mixin] || Resource
        @introspected = Set.new
        dir = opts[:directory]
        load_dir(dir) if dir
      end
      
      private
      
      # Enables the given class {Metadata} if necessary.
      #
      # @param [Class] klass the class to enable
      def ensure_metadata_introspected(klass)
        add_metadata(klass) unless @introspected.include?(klass)
      end
      
      # Enables the given class meta-data.
      #
      # @param [Class] klass the class to enable
      def add_metadata(klass)
        # Mark the class as introspected. Do this first to preclude a recursive loop back
        # into this method when the references are introspected in add_metadata.
        @introspected << klass
        # the package module
        mod = klass.parent_module
        # Add the superclass metadata, if necessary.
        sc = klass.superclass
        unless @introspected.include?(sc) or sc.parent_module != mod then
          resource_import(sc)
        end
        # Include the mixin.
        unless klass < @mixin then
          mixin = @mixin
          klass.class_eval { include mixin }
        end
        # Add the class metadata.
        case @metadata
          when Module then klass.extend(@metadata)
          when Proc then @metadata.call(klass)
          else raise MetadataError.new("#{self} metadata is neither a class nor a proc: #{@metadata.qp}")
        end
        klass.domain_module = self
        # Add referenced domain class metadata as necessary.
        klass.each_attribute_metadata do |attr_md|
          ref = attr_md.type
          if ref.nil? then raise MetadataError.new("#{self} #{attr_md} domain type is unknown.") end
          unless @introspected.include?(ref) or ref.parent_module != mod then
            logger.debug { "Adding #{qp} #{attr_md} reference #{ref.qp} metadata..." }
            resource_import(ref)
          end
        end
      end
      
      # Loads the Ruby source files in the given directory.
      #
      # @param [String] dir the source directory
      def load_dir(dir)
        # Auto-load the files on demand.
        syms = autoload_dir(dir)
        # Load each file on demand.
        syms.each do |sym|
          klass = const_get(sym)
          logger.info(klass.pp_s)
        end
      end
  
      # Auto-loads the Ruby source files in the given directory.
      #
      # @param [String] dir the source directory
      # @return [<Symbol>] the class constants that will be loaded
      def autoload_dir(dir)
        # the domain class definitions
        srcs = Dir.glob(File.join(dir, "*.rb"))
        # autoload the domain classes to ensure that definitions are picked up on demand in class hierarchy order
        srcs.map do |file|
          base_name = File.basename(file, ".rb")
          sym = base_name.camelize.to_sym
          # JRuby autoload of classes defined in a submodule of a Java wrapper class is not supported.
          # However, this only occurs with the caTissue Specimen Pathology annotation class definitions,
          # not the caTissue Participant or SCG annotations. TODO - confirm, isolate and report.
          # Work-around is to require the files instead.
          if name[/^Java::/] then
            require file
          else
            autoload(sym, file)
          end
          sym
        end    
      end
    end
  end
end