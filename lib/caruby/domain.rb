require 'fileutils'
require 'caruby/util/collection'
require 'caruby/domain/importer'

module CaRuby
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
    # The application start-up properties. The properties are defined in the properties
    # file or as environment variables. The properties file path is a period followed by
    # the lower-case application name in the home directory, e.g. +~/.clincaltrials+ for the
    # +ClinicalTrials+ application.
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
    # @return [{Symbol => Object}] the caBIG application access properties
    attr_reader :properties
       
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
    
    # Loads the {#properties} and adds the +path+ property items to the Java classpath.
    #
    # @param [Module] mod the module to extend
    def self.extended(mod)
      super
      mod.load_properties
    end
    
    # Loads the application {#properties}. If the {#properties} includes
    # a +:path+ entry, then the application client classpath is defined. This method
    # is called when a module extends this Domain, before any application Java domain
    # class is imported into JRuby.
    def load_properties
      # the properties file
      file = default_properties_file
      # the access properties
      props = file && File.exists?(file) ? load_properties_file(file) : {}
      # Load the Java application jar path.
      path = props[:classpath] || props[:path]
      if path then
        Java.add_path(path)
      end
      @properties = props
    end

    private
    
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