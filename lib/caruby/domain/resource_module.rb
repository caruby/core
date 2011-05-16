require 'fileutils'
require 'caruby/util/collection'
require 'caruby/util/log'

module CaRuby
  class JavaImportError < StandardError; end;

  # The application and database connection access command line options.
  ACCESS_OPTS = [
      [:user, "--user USER", "the application login user"],
      [:password, "--password PSWD", "the application login password"],
      [:host, "--host HOST", "the application host name"],
      [:port, "--port PORT", "the application port number"],
      [:classpath, "--classpath PATH", "the application client classpath"],
      [:database_host, "--database_host HOST", "the database host name"],
      [:database_type, "--database_type TYPE", "the database type (mysql or oracle)"],
      [:database_driver, "--database_driver DRIVER", "the database driver string"],
      [:database_driver_class, "--database_driver_class CLASS", "the database driver class name"],
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
  # The properties are read from a property file. See {Properties} for
  # more information.
  #
  # A Java class is imported into Ruby either by directly calling the extended
  # module {#resource_import} method or on demand by referencing the class name.
  # Import on demand is induced by a reference to the class, e.g.:
  #   module ClinicalTrials
  #     extend CaRuby::ResourceModule
  #
  #     @java_package = 'org.nci.ctms'
  #     ...
  # enables references by name to a +ClinicalTrials+ Ruby class wrapper of a
  # +org.nci.ctms+ Java class without an import statement, e.g.:
  #   ClinicalTrials::Participant.new
  # without defining the +Participant+ Ruby class.
  module ResourceModule
    # Loads the {#access_properties} and adds the path property items to the Java classpath.
    # @param [Module] mod the module to extend
    def self.extended(mod)
      super
      mod.ensure_classpath_defined
    end
    
    # Loads the application start-up properties on demand. The properties are defined in the properties
    # file or as environment variables.
    # The properties file path is a period followed by the lower-case application name in the home directory,
    # e.g. +~/.clincaltrials+ for the +ClinicalTrials+ application.
    #
    # The property file format is a series of property definitions in the form _property_: _value_.
    # The supported properties include the following:
    # * +host+ - the application server host (default +localhost+)
    # * +port+ - the application server port (default +8080+)
    # * +user+ - the application server login
    # * +password+ - the application service password
    # * +path+ or +classpath+ - the application client Java directories
    # * +database+ - the application database name
    # * +database_user+ - the application database connection userid
    # * +database_password+ - the application database connection password
    # * +database_host+ - the application database connection host (default +localhost+)
    # * +database_type+ - the application database type, + mysql+ or +oracle+ (default +mysql+)
    # * +database_driver+ - the application database connection driver (default is the database type default)
    # * +database_port+ - the application database connection port (default is the database type default)
    #
    # The +path+ value is one or more directories separated by a semi-colon(;) or colon (:)
    # Each path directory and all jar files within the directory are added to the caRuby execution
    # Java classpath.
    #
    # Each property has an environment variable counterpart given by 
    #
    # @return [{Symbol => Object}] the caBIG application access properties
    def access_properties
      @rsc_props ||= load_access_properties
    end
    
    # Ensures that the application client classpath is defined. The classpath is defined
    # in the {#access_properties}. This method is called when a module extends this
    # ResourceModule, before any application Java domain class is imported into JRuby.
    def ensure_classpath_defined
      # Loading the access properties on demand sets the classpath.
      access_properties
    end
    
    # @return [Module] the resource mix-in module (default {Resouce})
    def mixin
      @mixin || Resource
    end
    
    # Adds the given class to this ResourceModule. The class is extended with ResourceMetadata methods.
    #
    # @param [Class] the {Resource} class to add
    def add_class(klass)
      logger.debug { "Adding #{klass.java_class.name} to #{qp}..." }
      @rsc_classes ||= Set.new
      # add superclass if necessary
      sc = klass.superclass
      unless @rsc_classes.include?(sc) then
        # the domain module includes the superclass on demand
        sc_pkg, sc_sym = Java.split_class_name(sc)
        if const_defined?(sc_sym) or sc_pkg == @java_package then
          const_get(sc_sym)
        else
          mod = mixin
          klass.class_eval { include mod }
        end
      end
      ResourceMetadata.extend_class(klass, self)
      @rsc_classes << klass
      class_added(klass)
      logger.debug { "#{klass.java_class.name} added to #{qp}." }
    end

    # Auto-loads the Ruby source files in the given directory.
    #
    # @param [String] dir the source directory
    def load_dir(dir)
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
      sym_file_hash.to_a.each do |sym, file|
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
    
    # @param [Class, String] class_or_name the class to import into this module
    # @return [Class] the imported {Resource} class
    def resource_import(class_or_name)
      klass = java_import(class_or_name)
      mod = mixin
      klass.instance_eval { include mod }
      add_class(klass)
      klass
    end

    # Imports a class constant on demand. See the class documentation for details.
    #
    # @param [Symbol] symbol the missing constant
    def const_missing(symbol)
      autoload?(symbol) ? super : import_domain_class(symbol)
    end

    # @param [String] the class name to check
    # @eturn [Class, nil] the domain class for the class name, or nil if none in this module
    def domain_type_with_name(name)
      pkg, base = Java.split_class_name(name)
      return unless pkg.nil? or pkg == @java_package
      begin
        type = const_get(base)
      rescue JavaImportError
        # no such domain type; not an error.
        # other exceptions indicate that there was a domain type but could not be loaded; these exceptions propagate up the call stack
        logger.debug($!)
        return
      end
      type if type < Resource
    end

    private

    # Callback invoked after the given domain class is added to this domain module.
    #
    # @param [Class] klass the class that was added
    def class_added(klass); end
    
    # Loads the application start-up properties in the given file path.
    #
    # @return (see #access_properties)
    def load_access_properties
      # the properties file
      file = default_properties_file
      # the access properties
      props = file && File.exists?(file) ? load_properties_file(file) : {}
      # Look for environment overrides preceded by the uppercase module name,
      # e.g. CATISSUE_USER for the CaTissue module.
      load_environment_properties(props)
      
      # load the Java application jar path
      path = props[:classpath] || props[:path]
      if path then
        logger.info("Defining application classpath #{path}...")
        Java.add_path(path)
      end
      
      props
    end
    
    def load_properties_file(file)
      props = {}
      logger.info("Loading application properties from #{file}...")
      File.open(file).map do |line|
        # match the tolerant property definition
        match = PROP_DEF_REGEX.match(line.chomp) || next
        # the property [name, value] tokens
        tokens = match.captures
        pname = tokens.first.to_sym
        # path is deprecated
        name = pname == :path ? :classpath : pname
        value = tokens.last
        # capture the property
        props[name] = value
      end
      props
    end
    
    def load_environment_properties(props)
      ACCESS_OPTS.each do |spec|
        # the access option symbol is the first specification item
        opt = spec[0]
        # the envvar value
        value = environment_property(opt) || next
        # override the file property with the envar value
        props[opt] = value
        logger.info("Set application property #{opt} from environment variable #{ev}.")
      end
    end 
    
    # @param [Symbol] opt the property symbol, e.g. :user
    # @return [String, nil] the value of the corresponding environment variable, e.g. +CATISSUE_USER+
    def environment_property(opt)
      @env_prefix ||= name.gsub('::', '_').upcase
      ev = "#{@env_prefix}_#{opt.to_s.upcase}"
      value = ENV[ev]
      # If no classpath envvar, then try the deprecated path envvar.
      if value.nil? and opt == :classpath then
        environment_property(:path)
      else
        value
      end
    end
    
    # Imports the domain Java class with specified class name_or_sym.
    # This method enables the domain class extensions for storing and retrieving domain objects.
    # The class is added to this module.
    #
    # The optional block overrides the native Java property access wrappers.
    # For example:
    #   ClinicalTrials.java_import Java::edu.wustl.catissuecore.domain.Study do
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
    #
    # @param [Symbol] symbol the class symbol
    # @param [String, nil] pkg the Java class package name, or nil for the default module package
    def import_domain_class(symbol, pkg=nil)
      # check if the class is already defined
      if const_defined?(symbol) then
        klass = const_get(symbol)
        if domain?(klass) then
          logger.warn("Attempt to import #{self.qp} class twice: #{symbol}.") and return klass
        end
      end
      
      # import the Java class
      pkg ||= @java_package
      name = [pkg, symbol.to_s].join('.')
      logger.debug { "Detecting whether #{symbol} is a #{pkg} Java class..." }
      # Push each imported class onto a stack. When all referenced classes are imported,
      # each class on the stack is post-initialized and the class structure is printed to
      # the log.
      @import_stack ||= []
      @import_stack.push(symbol)
      begin
        resource_import(name)
      rescue JavaImportError
        @import_stack.pop
        raise
      end
      
      # the imported Java class is registered as a constant in this module
      klass = const_get(symbol)
      # if we are back to top of the stack, then print the imported Resources
      if symbol == @import_stack.first then
        # a referenced class could be imported on demand in the course of printing a referencing class;
        # the referenced class is then pushed onto the stack. thus, the stack can grow during the
        # course of printing, but each imported class is consumed and printed in the end.
        until @import_stack.empty? do
          # the class constant
          sym = @import_stack.pop
          # the imported class
          kls = const_get(sym)
          # invoke the call-back
          imported(kls)
          # print the class structure to the log
          logger.info(kls.pp_s)
        end
      end
      
      klass
    end

    # Call-back to perform post-import actions. This method is called after the
    # given class and each of its referenced domain classes are introspected.
    #
    # @param [Class] the imported class
    def imported(klass); end

    # The property/value matcher, e.g.:
    #   host: jacardi
    #   host = jacardi
    #   host=jacardi
    #   name: J. Edgar Hoover
    # but not:
    #   # host: jacardi
    # The captures are the trimmed property and value
    PROP_DEF_REGEX = /^(\w+)(?:\s*[:=]\s*)([^#]+)/
    
    # @return [String] the default application properties file, given by +~/.+_name_,
    #   where _name_ is the underscore unqualified module name, e.g. +~/.catissue+
    #   for module +CaTissue+
    def default_properties_file
      home = ENV['HOME'] || ENV['USERPROFILE'] || '~'
      file = File.expand_path("#{home}/.#{name[/\w+$/].downcase}")
      if File.exists?(file) then
        file
      else
        logger.warn("The default #{name} application property file was not found: #{file}.")
        nil
      end
    end
  end
end