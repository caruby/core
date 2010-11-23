require 'caruby/util/collection'
require 'caruby/util/validation'
require 'caruby/util/merge'

# Options is a utility class to support method options.
class Options
  # Returns the value of option in options as follows:
  # * If options is a hash which contains the option key, then this method returns
  #   the option value. A non-collection options[option] value is wrapped as a singleton
  #   collection to conform to a collection default type, as shown in the example below.
  # * If options equals the option symbol, then this method returns +true+.
  # * If options is an Array of symbols which includes the given option, then this method
  #   returns +true+.
  # * Otherwise, this method returns the default.
  #
  # If default is nil and a block is given to this method, then the default is determined
  # by calling the block with no arguments. The block can also be used to raise a missing
  # option exception, e.g.:
  #   Options.get(:userid, options) { raise RuntimeError.new("Missing required option: userid") }
  #
  # @example
  #   Options.get(:create, {:create => true}) #=> true
  #   Options.get(:create, :create) #=> true
  #   Options.get(:create, [:create, :compress]) #=> true
  #   Options.get(:create, nil) #=> nil
  #   Options.get(:create, nil, :false) #=> false
  #   Options.get(:create, nil, :true) #=> true
  #   Options.get(:values, nil, []) #=> []
  #   Options.get(:values, {:values => :a}, []) #=> [:a]
  def self.get(option, options, default=nil, &block)
    return default(default, &block) if options.nil?
    case options
    when Hash then
      value = options[option]
      value.nil? ? default(default, &block) : value
    when Enumerable then
      options.include?(option) ? true : default(default, &block)
    when Symbol then
      option == options ? true : default(default, &block)
    else
      raise ArgumentError.new("Options argument type is not supported; expected Hash or Symbol, found: #{options.class}")
    end
  end

  # Merges the others options with options and returns the new merged option hash.
  #
  # @example
  #   Options.merge(nil, :create) #=> {:create => :true}
  #   Options.merge(:create, :optional => :a, :required => :b) #=> {:create => :true, :optional => :a, :required => :b}
  #   Options.merge({:required => [:b]}, :required => [:c]) #=> {:required => [:b, :c]}
  def self.merge(options, others)
    options = options.dup if Hash === options
    self.merge!(options, others)
  end

  # Merges the others options into the given options and returns the created or modified option hash.
  # This method differs from {Options.merge} by modifying an existing options hash.
  def self.merge!(options, others)
    to_hash(options).merge!(to_hash(others)) { |key, oldval, newval| oldval.respond_to?(:merge) ? oldval.merge(newval) : newval }
  end

  # Returns the options as a hash. If options is already a hash, then this method returns hash.
  # * If options is a Symbol _s_, then this method returns +{+_s_+=>true}+.
  # * An Array of Symbols is enumerated as individual Symbol options.
  # * If options is nil, then this method returns a new empty hash.
  def self.to_hash(options)
    return Hash.new if options.nil?
    case options
    when Hash then
      options
    when Array then
      options.to_hash { |item| Symbol === item or raise ArgumentError.new("Option is not supported; expected Symbol, found: #{options.class}") }
    when Symbol then
      {options => true}
    else
      raise ArgumentError.new("Options argument type is not supported; expected Hash or Symbol, found: #{options.class}")
    end
  end

  # Raises a ValidationError if the given options are not in the given allowable choices.
  def self.validate(options, choices)
    to_hash(options).each_key do |opt|
      raise ValidationError.new("Option is not supported: #{opt}") unless choices.include?(opt)
    end
  end

  private

  def self.default(value)
    value.nil? && block_given? ? yield : value
  end
end