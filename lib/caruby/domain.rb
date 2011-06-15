require 'fileutils'
require 'caruby/util/collection'
require 'caruby/util/log'
require 'caruby/domain/importer'

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

  # Domain extends a Module with Java class {Metadata} support.
  #
  # A Java class is imported into Ruby either by including the given Resource module
  # or by referenceing the class name for the first time. For example, the
  # +ClinicalTrials+ wrapper for Java package +org.nci.ctms+ classes and
  # Ruby class definitions in the +domain+ subdirectory is enabled as follows:
  #   module ClinicalTrials
  #     PKG = 'org.nci.ctms'
  #     SRC_DIR = File.join(File.dirname(__FILE__), 'domain')
  #     CaRuby::Domain.extend_module(self, :package => PKG, :directory => SRC_DIR)
  #
  # The first reference by name to +ClinicalTrials::Subject+ imports the Java class
  # +org.nci.ctms.Subject+ into +ClinicalTrials+. The +Subject+ Java property meta-data
  # is introspected and the {Resource} module is included.
  module Domain
    # Extends the given module with importable Java class {Metadata} support.
    #
    # @param [Module] mod the module to extend
    # @param [{Symbol => Object}] opts the extension options
    # @option opts [Module] :metadata the optional {Metadata} extension (default {Metadata})
    # @option opts [Module] :mixin the optional mix-in module (default {Resource})
    # @option opts [String] :package the required Java package name
    # @option opts [String] :directory the optional directory of source class definitions to load
    def self.extend_module(mod, opts)
      mod.extend(self)
      Importer.extend_module(mod, opts)
    end
    
    # Loads the {#access_properties} and adds the +path+ property items to the Java classpath.
    #
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
    # Domain, before any application Java domain class is imported into JRuby.
    def ensure_classpath_defined
      # Loading the access properties on demand sets the classpath.
      access_properties
    end
    
#    # @param [Class, String] class_or_name the class to import into this module
#    # @return [Class] the imported {Resource} class
#    def resource_import(class_or_name)
#      java_import(class_or_name)
#      klass = Class.to_ruby(class_or_name)
#      add_class(klass)
#      klass
#    end
#
#    # @param [String] the class name to check
#    # @eturn [Class, nil] the domain class for the class name, or nil if none in this module
#    def domain_type_with_name(name)
#      pkg, base = Java.split_class_name(name)
#      return unless pkg.nil? or pkg == @java_package
#      begin
#        type = const_get(base)
#      rescue JavaImportError => e
#        # no such domain type; not an error.
#        # other exceptions indicate that there was a domain type but could not be loaded; these exceptions propagate up the call stack
#        logger.debug { "#{$!}" }
#        return
#      end
#      type if type < Resource
#    end

    private
    
#    # Adds the given class to this domain module. The class is extended with {Metadata} methods.
#    #
#    # @param [Class] the {Resource} class to add
#    def add_class(klass)
#      # This domain module's known Resource classes.
#      @rsc_classes ||= Set.new
#      # Bail if already added.
#      return if @rsc_classes.include?(klass)
#
#      logger.debug { "Adding #{klass.java_class.name} to #{qp}..." }
#      # Add metadata to the class. This is done before adding the superclass and
#      # referenced metadata, since they in turn might reference the current class
#      # metadata.
#      Metadata.extend_class(klass, self)
#      # Add the class to the known Resource class set.
#      @rsc_classes << klass
#      
#      # Make the superclass a Resource, if necessary.
#      sc = klass.superclass
#      unless @rsc_classes.include?(sc) then
#        # the domain module includes the superclass on demand
#        pkg, sym = Java.split_class_name(sc)
#        if pkg == @java_package then
#          # Load the superclass on demand; don't need to make this class a Resource,
#          # but do need to import the class.
#          const_get(sym)
#        else
#          # Superclass is not a member of the domain package; make this class a Resource.
#          mod = @mixin
#          klass.class_eval { include mod }
#        end
#      end
#
#      # Add referenced domain classes as necessary.
#      klass.each_attribute_metadata do |attr_md|
#        ref = attr_md.type
#        next if @rsc_classes.include?(ref)
#        pkg, sym = Java.split_class_name(ref)
#        # This domain module adds a referenced Domain class on demand.
#        if pkg == @java_package then
#          puts "rm ac1 #{klass} #{attr_md} -> #{ref}..."
#          logger.debug { "Loading #{klass.qp} #{attr_md} reference #{ref.qp}" }
#          const_get(sym)
#        end
#      end
#      
#      # Invoke the callback.
#      class_added(klass)
#      logger.debug { "#{klass.java_class.name} added to #{qp}." }
#      # print the class structure to the log
#      logger.info(klass.pp_s)
#    end
#    
#    # Callback invoked after the given domain class is added to this domain module.
#    #
#    # @param [Class] klass the class that was added
#    def class_added(klass); end
   
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
        match = PROP_DEF_REGEX.match(line.chomp.strip) || next
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
#    
#    # Imports the domain Java class with specified class name_or_sym.
#    # This method enables the domain class extensions for storing and retrieving domain objects.
#    # The class is added to this module.
#    #
#    # The optional block overrides the native Java property access wrappers.
#    # For example:
#    #   ClinicalTrials.java_import Java::edu.wustl.catissuecore.domain.Study do
#    #     def study_code=(value)
#    #       value = value.to_s if Integer === value
#    #       setStudyCode(value)
#    #     end
#    #   end
#    # imports the ClinicalTrials Study class as ClinicalTrials::Study and overrides the
#    # +study_code+ setter method.
#    #
#    # Convenience aliases are added to the imported class, e.g. attribute +studyParticipantCollection+
#    # is aliased as +study_participants+. Specifically, each attribute reader and writer is aliased with
#    # the lower-case, underscore equivalent and a name ending in 'Collection' is changed to plural.
#    # Pluralization is smart, e.g. +studyCollection+ is aliased to +studies+ rather than +studys+.
#    #
#    # The optional aliases argument consists of additional alias => standard attribute associations.
#    # The optional owner_attr argument is a non-Java annotation owner attribute.
#    #
#    # @param [Symbol] symbol the class symbol
#    # @param [String, nil] pkg the Java class package name, or nil for the default module package
#    # @return [Class] the imported domain class
#    def import_domain_class(symbol, pkg=nil)
#      # import the Java class
#      pkg ||= @java_package
#      name = [pkg, symbol.to_s].join('.')
#      logger.debug { "Detecting whether #{symbol} is a #{pkg} Java class..." }
#      # Push each imported class onto a stack. When all referenced classes are imported,
#      # each class on the stack is post-initialized and the class structure is printed to
#      # the log.
#      @import_stack ||= []
#      @import_stack.push(symbol)
#      begin
#        resource_import(name)
#      ensure
#        @import_stack.pop
#      end
#      
#      # the imported Java class is registered as a constant in this module
#      klass = const_get(symbol)
#      add_class(klass)
#      
#      # if we are back to top of the stack, then print the imported Resources
#      if symbol == @import_stack.first then
#        # a referenced class could be imported on demand in the course of printing a referencing class;
#        # the referenced class is then pushed onto the stack. thus, the stack can grow during the
#        # course of printing, but each imported class is consumed and printed in the end.
#        until @import_stack.empty? do
#          # the class constant
#          sym = @import_stack.pop
#          # the imported class
#          kls = const_get(sym)
#          # print the class structure to the log
#          logger.info(kls.pp_s)
#        end
#      end
#      
#      klass
#    end

    # The property/value matcher, e.g.:
    #   host: jacardi
    #   host = jacardi
    #   host=jacardi
    #   name: J. Edgar Hoover
    # but not:
    #   # host: jacardi
    # The captures are the trimmed property and value.
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