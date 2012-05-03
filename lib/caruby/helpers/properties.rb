require 'yaml'
require 'set'
require 'jinx/helpers/pretty_print'
require 'jinx/helpers/collection'
require 'jinx/helpers/merge'

module CaRuby
  # Exception raised if a configuration property is missing or invalid.
  class ConfigurationError < RuntimeError; end

  # A Properties instance encapsulates a properties file accessor. The properties are stored
  # in YAML format.
  class Properties < Hash
    # Creates a new Properties object. If the file argument is given, then the properties are loaded from
    # that file.
    #
    # Supported options include the following:
    # * :merge - the properties which are merged rather than replaced when loaded from the property files
    # * :required - the properties which must be set when the property files are loaded
    # * :array - the properties whose comma-separated String input value is converted to an array value
    def initialize(file=nil, options=nil)
      super()
      @merge_properties = Options.get(:merge, options, []).to_set
      @required_properties = Options.get(:required, options, []).to_set
      @array_properties = Options.get(:array, options, []).to_set
      load_properties(file) if file
    end

    # Returns a new Hash which associates this Properties' keys converted to symbols to the respective values.
    def symbolize
      Hash.new
    end

    # Returns whether the property key or its alternate is defined.
    def has_property?(key)
      has_key?(key) or has_key?(alternate_key(key))
    end

    # Returns the property value for the key. If there is no String key entry but there is a
    # alternate key entry, then this method returns the alternate key value.
     def [](key)
      super(key) or super(alternate_key(key))
    end

    # Returns the property value for the key. If there is no key entry but there is an
    # alternate key entry, then alternate key entry is set.
    def []=(key, value)
      return super if has_key?(key)
      alt = alternate_key(key)
      has_key?(alt) ? super(alt, value) : super
    end

    # Deletes the entry for the given property key or its alternate.
    def delete(key)
      key = alternate_key(key) unless has_key?(key)
      super
    end

    # Loads the specified properties file, replacing any existing properties.
    #
    # If a key is included in this Properties merge_properties array, then the
    # old value for that key will be merged with the new value for that key
    # rather than replaced.
    #
    # This method reloads a property file that has already been loaded.
    #
    # Raises ConfigurationError if file doesn't exist or couldn't be parsed.
    def load_properties(file)
      raise ConfigurationError.new("Properties file not found: #{File.expand_path(file)}") unless File.exists?(file)
      properties = {}
      begin
        YAML::load_file(file).each { |key, value| properties[key.to_sym] = value }
      rescue
        raise ConfigurationError.new("Could not read properties file #{file}: " + $!)
      end
      # Uncomment the following line to print detail properties.
      #logger.debug { "#{file} properties:\n#{properties.pp_s}" }
      # parse comma-delimited string values of array properties into arrays
      @array_properties.each do |key|
        value = properties[key]
        if String === value then
          properties[key] = value.split(/,\s*/)
        end
      end
      # if the key is a merge property key, then perform a deep merge.
      # otherwise, do a shallow merge of the property value into this property hash.
      deep, shallow = properties.split { |key, value| @merge_properties.include?(key) }
      merge!(deep, :deep)
      merge!(shallow)
    end

    private

    # Returns key as a Symbol if key is a String, key as a String if key is a Symbol,
    # or nil if key is neither a String nor a Symbol.
    def alternate_key(key)
      case key
        when String then key.to_sym
        when Symbol then key.to_s
      end
    end

    # Validates that the required properties exist.
    def validate_properties
      @required_properties.each do |key|
        raise ConfigurationError.new("A required #{@application} property was not found: #{key}") unless has_property?(key)
      end
    end
  end
end