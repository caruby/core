require 'caruby/domain/metadata_loader'

module CaRuby
  module Domain
    # Importer extends a module with Java class import support.
    #
    # A Java class is imported into JRuby on demand by referencing the class name.
    # Import on demand is induced by a reference to the class.
    # The +clincal_trials+ example illustrates a domain package extended
    # with metadata capability. The first reference by name to +ClinicalTrials::Subject+
    # imports the Java class +clincal_trials.domain.Subject+ into the JRuby class wrapper
    # +ClinicalTrials::Subject+. The +ClinicalTrials::Resource+ module is included
    # in +ClinicalTrials::Subject+ and the Java property meta-data is introspected.
    module Importer
      include MetadataLoader
      
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
        # The symbol might be a class defined in the source directory.
        # If that is the case, then initialize the introspected set, which
        # loads the source directory.
        unless defined? @introspected then
          initialize_introspected
          return const_get(symbol)
        end
        # Append the symbol to the package to make the Java class name.
        begin
          klass = java_import "#{@pkg}.#{symbol}"
        rescue NameError
          # Not a Java class; print a log message and pass along the error.
          logger.warn { "#{symbol} is not recognized as a #{@pkg} Java class - #{$!}\n#{caller.qp}." }
          super
        end
        # Introspect the Java class meta-data, if necessary.
        unless @introspected.include?(klass) then
          add_metadata(klass) 
          logger.info(klass.pp_s)
        end
        
        klass
      end
    
      # Imports the given Java class and introspects the {Metadata}.
      # The Java class is assumed to be defined in this module's package.
      # This module's mixin is added to the class.
      #
      # @param [Class] klass the source directory
      # @raise [NameError] if the symbol does not correspond to a Java class
      #   in this module's package
      # @return [Class, nil] the imported class, or nil if the class was already introspected
      def resource_import(klass)
        # Import the Java class.
        java_import(klass)
        # If this is the first imported class, then load the class definitions.
        unless defined? @introspected then initialize_introspected end
        # Introspect the Java class meta-data, if necessary.
        add_metadata(klass) unless @introspected.include?(klass)
        klass
      end
      
      # Declares that the given {Resource} classes will be dynamically modified.
      # This method auto-loads the classes, if necessary.
      #
      # @param [<Class>] classes the classes to modify
      def shims(*classes)
        # Nothing to do, since all this method does is ensure that the arguments are
        # auto-loaded when they are referenced.
      end

      # Configures this importer with the given options. This method is intended for use by the
      # +extend_module+ method.
      #
      # The imported class is extended with {Metadata}. If the +:metadata+ option is set to a
      # class, then the class is extended with that module as well. If the +:metadata+ option
      # is set to a proc, then the extender proc is called with the class as a parameter. 
      #
      # @param [{Symbol => Object}] opts the extension options
      # @option opts [String] :package the required Java package name
      # @option opts [Module, Proc] :metadata the optional application-specific extension module or proc
      # @option opts [Module] :mixin the optional mix-in module (default {Resource})
      # @option opts [String] :directory the optional directory of source class definitions to load
      def configure_importer(opts)
        @pkg = opts[:package]
        if @pkg.nil? then CaRuby.fail(ArgumentError, "Required domain package option not found") end
        @metadata = opts[:metadata]
        @mixin = opts[:mixin] || Resource
        @directory = opts[:directory]
      end
      
      private
      
      # Declares the +introspected+ instance variable and loads the source directory, if it is defined.
      def initialize_introspected
        @introspected = Set.new
        load_dir(@directory) if @directory
      end

      # Loads the Ruby source files in the given directory.
      #
      # @param [String] dir the source directory
      def load_dir(dir)
        logger.debug { "Loading the class definitions in #{@directory}..." }
        # Auto-load the files.
        syms = autoload_dir(dir)
        # Load each file on demand.
        loaded = syms.map { |sym| klass = const_get(sym) }
        # Print the introspected class content.
        @introspected.each { |klass| logger.info(klass.pp_s) }
        logger.debug { "Loaded the class definitions in #{dir}." }
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