require 'caruby/helpers/collection'
require 'caruby/helpers/validation'
require 'caruby/helpers/merge'

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
  #   Options.get(:userid, options) { CaRuby.fail(RuntimeError, "Missing required option: userid") }
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
        if String === value then value.strip! end
        value.nil_or_empty? ? default(default, &block) : value
      when Enumerable then
        options.include?(option) ? true : default(default, &block)
      when Symbol then
        option == options ? true : default(default, &block)
      else
        CaRuby.fail(ArgumentError, "Options argument type is not supported; expected Hash or Symbol, found: #{options.class}")
    end
  end

  # Returns the given argument list as a hash, determined as follows:
  # * If the sole argument member is a hash, then that hash is the options.
  # * An argument list of option symbols followed by zero, one or more non-option parameters is composed as the option hash.
  # * An empty argument list is a new empty option hash.
  #
  # @example
  #   Options.to_hash() #=> {}
  #   Options.to_hash(nil) #=> {}
  #   Options.to_hash(:a => 1) #=> {:a => 1}
  #   Options.to_hash(:a) #=> {:a => true}
  #   Options.to_hash(:a, 1, :b, 2) #=> {:a => 1, :b => 2}
  #   Options.to_hash(:a, 1, :b, :c, 2, 3) #=> {:a => 1, :b => true, :c => [2, 3]}
  # @param [Array] args the option list
  # @return [Hash] the option hash
  def self.to_hash(*args)
    unless Enumerable === args then
      CaRuby.fail(ArgumentError, "Expected Enumerable, found #{args.class.qp}")
    end
    oargs = {}
    opt = args.first
    return oargs if opt.nil?
    return opt if oargs.empty? and Hash === opt
    unless Symbol === opt then
      CaRuby.fail(ArgumentError, "Expected Symbol as first argument, found #{args.first.class.qp}")
    end
    args.inject(nil) do |list, item|
      Symbol === item ? oargs[item] = Array.new : list << item
    end
    # convert the value list to true, a single value or leave as an array
    oargs.transform do |list|
      case list.size
        when 0 then true
        when 1 then list.first
        else list
      end
    end.to_hash
  end

  # @param [Hash, Symbol, nil] opts the options to validate
  # @raise [ValidationError] if the given options are not in the given allowable choices
  def self.validate(options, choices)
    to_hash(options).each_key do |opt|
      CaRuby.fail(ValidationError, "Option is not supported: #{opt}") unless choices.include?(opt)
    end
  end

  private

  def self.default(value)
    value.nil? && block_given? ? yield : value
  end
end