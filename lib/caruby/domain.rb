require 'fileutils'
require 'caruby/util/collection'
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

  # This Domain module extends an application domain module with Java class {Metadata}
  # support. The metadata introspection enables the jRuby-Java API bridge.
  #
  # A Java class is imported as a Domain class in two ways:
  # * the +resource_import+ declaration
  # * referencing the class name for the first time in the domain module context
  #
  # For example, if the +ClinicalTrials+ module wraps the +clinicaltrials.domain+
  # Java application package by extending +Domain+, then the first reference by
  # name to +ClinicalTrials::Subject+ imports the Java application class
  # +clinicaltrials.domain.Subject+ into +ClinicalTrials+ and introspects the
  # +Subject+ Java property meta-data.
  #
  # @example
  #   module ClinicalTrials
  #     CaRuby::Domain.extend_module(self, :mixin => Resource, :package => 'clinicaltrials.domain')
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

    private
       
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
        Java.add_path(path)
      end
      
      props
    end
    
    def load_properties_file(file)
      props = {}
      #logger.info("Loading application properties from #{file}...")
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
      file if File.exists?(file)
    end
  end
end