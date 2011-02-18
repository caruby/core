require 'fileutils'
require 'caruby/util/collection'
require 'caruby/util/log'

module CaRuby
  class JavaIncludeError < StandardError; end;

  # The application and database connection access command line options.
  ACCESS_OPTS = [
      [:user, "--user USER", "the application login user"],
      [:password, "--password PSWD", "the application login password"],
      [:host, "--host HOST", "the application host name"],
      [:database_host, "--database_host HOST", "the database host name"],
      [:database_type, "--database_type TYPE", "the database type (mysql or oracle)"],
      [:database_driver, "--database_driver DRIVER", "the database driver"],
      [:database_port, "--database_port PORT", Integer, "the database port number"],
      [:database, "--database NAME", "the database name"],
      [:database_user, "--database_user USER", "the database login user"],
      [:database_password, "--database_password PSWD", "the database login password"]
    ]

  # Importable extends a Module with Java class support.
  # The calling module must implement the following instance variables:
  # * +*java_package+ - the module Java package name
  # * +@mixin+ - the module which scopes the domain objects
  # See the ClinicalTrials module for an example.
  #
  # The application properties hash specifies the startup information,
  # including the user, password and application Java jar library path.
  # The properties are read from a property file. See CaRuby::Properties for
  # more information.
  #
  # A Java class is imported into Ruby either by directly calling the
  # extended module {#java_import} method or on demand.
  # Import on demand is induced by a reference to the class, e.g.:
  #   module ClinicalTrials
  #     extend Importable
  #
  #     def java_package
  #       'org.nci.ctms'
  #     end
  #     ...
  # enables references by name to a +ClinicalTrials+ Ruby class wrapper of a
  # +org.nci.ctms+ Java class without an import statement, e.g.:
  #   ClinicalTrials::Participant.new
  # without defining the +Participant+ Ruby class.
  module ResourceModule
    # Adds the given klass to this ResourceModule. The class is extended with ResourceMetadata methods.
    def add_class(klass)
      @rsc_classes ||= Set.new
      # add superclass if necessary
      unless @rsc_classes.include?(klass.superclass) or klass.superclass == Java::JavaLang::Object then
        # the domain module includes the superclass on demand
        const_get(klass.superclass.name[/\w+$/].to_sym)
      end
      ResourceMetadata.extend_class(klass, self)
      @rsc_classes << klass
    end
    
    # @return [Module] the resource mix-in module (default {Resouce})
    def mixin
      @mixin || Resource
    end

    # @return [{Symbol => Object}] the caBIG application access properties
    # @see #load_access_properties
    def access_properties
      @resource_module__props ||= load_access_properties
    end

    # Loads the application start-up properties in the given file path.
    # The default file path is a period followed by the lower-case application name in the home directory,
    # e.g. +~/.clincaltrials+.
    #
    # The property file format is a series of property definitions in the form _property_: _value_.
    # The supported properties include the following:
    # * +path+ - the application client Java directories
    # * +user+ - the application service login
    # * +password+ - the application service password
    # * +database+ - the application database name
    # * +database_user+ - the application database connection userid
    # * +database_password+ - the application database connection password
    # * :database_host - the application database connection host (default +localhost+)
    # * +database_type+ - the application database type, + mysql+ or +oracle+ (default +mysql+)
    # * +database_driver+ - the application database connection driver (default is the database type default)
    # * +database_port+ - the application database connection port
    #
    # The +path+ value is one or more directories separated by a semi-colon(;) or colon (:)
    # Each path directory and all jar files within the directory are added to the caRuby execution
    # Java classpath.
    #
    # @param [String, nil] file the property file, or nil for the default location
    # @return [{Symbol => Object}] the loaded caBIG application access properties
    def load_access_properties(file=nil)
      # If a file was specified, then it must exist.
      if file and not File.exists?(file) then
        raise ArgumentError.new("Application access properties file does not exist: #{file}")
      end
      # the access properties
      @resource_module__props ||= {}
      # If no file was specified, then try the default.
      # If the default does not exist, then use the empty properties hash.
      # It is not an error to omit access properties, since the application domain classes
      # can still be used but not queried or saved.
      file ||= default_properties_file || return
      
      logger.info("Loading application properties from #{file}...")
      File.open(file).map do |line|
        # match the tolerant property definition
        match = PROP_DEF_REGEX.match(line.chomp) || next
        # the property [name, value] tokens
        tokens = match.captures
        name = tokens.first.to_sym
        value = tokens.last
        # capture the property
        @resource_module__props[name] = value
      end
      
      # Look for environment overrides preceded by the uppercase module name, e.g. CATISSUE
      # for the CaTissue module.
      env_prefix = name[/\w+$/].upcase
      ACCESS_OPTS.each do |spec|
        # the access option symbol is the first specification item
        opt = spec[0]
        # the envvar, e.g. CATISSUE_USER
        ev = "#{env_prefix}_#{opt.to_s.upcase}"
        # the envvar value
        value = ENV[ev] || next
        # override the file property with the envar value
        @resource_module__props[opt] = value
        logger.info("Set application property #{opt} from environment variable #{ev}.")
      end
      
      # load the Java application jar path
      path_ev = "#{env_prefix}_PATH"
      path = ENV[path_ev] || @resource_module__props[:path]
      Java.add_path(path) if path
      
      @resource_module__props
    end

    # Loads the Ruby source files in the given directory.
    def load_dir(dir)
      # load the properties on demand
      load_access_properties if @resource_module__props.nil?
      # the domain class definitions
      sources = Dir.glob(File.join(dir, "*.rb"))

      # autoload the domain classes to ensure that definitions are picked up on demand in class hierarchy order
      sym_file_hash = {}
      sources.each do |file|
        base_name = File.basename(file, ".rb")
        sym = base_name.camelize.to_sym
        sym_file_hash[sym] = file
        autoload(sym, file)
      end

      # load the domain class definitions
      sym_file_hash.each do |sym, file|
        require file
      end

      # print the loaded classes to the log
      sym_file_hash.each_key do |sym|
        # it is not an error if the inferred class name is not loaded, since only the Java application classes
        # are required to be the camel-case form of the file names.
        klass = const_get(sym) rescue next
        logger.info("#{klass.pp_s}")
      end
    end

    # Extends the mod module with Java class support. See the class documentation for details.
    #
    # @param [Symbol] symbol the missing constant
    def const_missing(symbol)
      autoload?(symbol) ? super : import_domain_class(symbol)
    end

    # Returns the domain class for class_name, or nil if none in this module.
    def domain_type_with_name(class_name)
      pkg, base = split_class_name(class_name)
      return unless pkg.nil? or pkg == @java_package
      begin
        type = const_get(base)
      rescue JavaIncludeError
        # no such domain type; not an error.
        # other exceptions indicate that there was a domain type but could not be loaded; these exceptions propagate up the call stack
        logger.debug("#{base} is not a #{qp} Java class.")
        return
      end
      type if type < Resource
    end

    private

    # Imports the domain Java class with specified class name_or_sym.
    # This method enables the domain class extensions for storing and retrieving domain objects.
    # The class is added to this module.
    #
    # The optional block overrides the native Java property access wrappers.
    # For example:
    #   ClinicalTrials.java_import('edu.wustl.catissuecore.domain.Study') do
    #     def study_code=(value)
    #       value = value.to_s if Integer === value
    #       setStudyCode(value)
    #     end
    #   end
    # imports the ClinicalTrials Study class as ClinicalTrials::Study and overrides the
    # +study_code+ setter method.
    #
    # Convenience aliases are added to the imported class, e.g. attribute +studyParticipantCollection+
    # is aliased as +study_participants+. Specifically, each attribute reader and writer is aliased with
    # the lower-case, underscore equivalent and a name ending in 'Collection' is changed to plural.
    # Pluralization is smart, e.g. +studyCollection+ is aliased to +studies+ rather than +studys+.
    #
    # The optional aliases argument consists of additional alias => standard attribute associations.
    # The optional owner_attr argument is a non-Java annotation owner attribute.
    def import_domain_class(name_or_sym)
      name = name_or_sym.to_s
      if name.include?('.') then
        symbol = name[/[A-Z]\w*$/].to_sym
      else
        symbol = name_or_sym.to_sym
        name = [@java_package, name].join('.')
      end
      # check if the class is already defined
      if const_defined?(symbol) then
        klass = const_get(symbol)
        if domain?(klass) then
          logger.warn("Attempt to import #{self.qp} class twice: #{symbol}.") and return klass
        end
      end
      
      # import the Java class
      logger.debug { "Importing #{qp} Java class #{symbol}..." }
      begin
        java_import(name)
      rescue Exception => e
        raise JavaIncludeError.new("#{symbol} is not a #{qp} Java class - #{e.message}")
      end
      
      # the imported Java class is registered as a constant in this module
      klass = const_get(symbol)
      # the Resource import stack
      @import_stack ||= []
      @import_stack.push klass
      # include the Resource mixin in the imported class
      inc = "include #{mixin}"
      klass.instance_eval(inc)
      
      # if we are back to top of the stack, then print the imported Resources
      if klass == @import_stack.first then
        # a referenced class could be imported on demand in the course of printing a referencing class;
        # the referenced class is then pushed onto the stack. thus, the stack can grow during the
        # course of printing, but each imported class is consumed and printed in the end.
        until @import_stack.empty? do
          ref = @import_stack.pop
          logger.debug { ref.pp_s }
        end
      end
      klass
    end

    # The property/value matcher, e.g.:
    #   host: jacardi
    #   host = jacardi
    #   host=jacardi
    #   name: J. Edgar Hoover
    # but not:
    #   # host: jacardi
    # The captures are the trimmed property and value
    PROP_DEF_REGEX = /^(\w+)(?:\s*[:=]\s*)([^#]+)/
    
    def default_properties_file
      home = ENV['HOME'] || '~'
      file = File.expand_path("#{home}/.#{name[/\w+$/].downcase}")
      if File.exists?(file) then
        file
      else
        logger.warn { "Default application property file not found: #{file}." }
        nil
      end
    end
    
    # @return [(String, Symbol)] the [package prefix, base class symbol] pair
    def split_class_name(class_name)
      # the package prefix, including the period
      package = Java.java_package_name(class_name)
      # remove the package and base class name
      base = package.nil? ? class_name : class_name[package.length + 1..-1]
      [package, base.to_sym]
    end
  end
end