require 'caruby/util/collection'

module CaRuby
  # Cache for objects held in memory and accessed by key.
  class Cache
    
    # The classes which are not cleared when {#clear} is called without the +all+ flag.
    attr_reader :sticky
    
    # Returns a new Cache whose value key is determined by calling the given
    # extractor block on the cached value.
    #
    # If the value is not cached and there is a factory Proc, then the result of
    # calling the factory on the missing value is cached with the value key.
    #
    # @param [Proc] optional factory Proc called with a missing value as argument
    #   to create a cached object
    def initialize(factory=nil, &extractor)
      @factory = factory
      # Make the class => { key => value } hash.
      # The { key => value } hash takes a value as an argument and converts
      # it to the key by calling the block given to this initializer.
      @hash = LazyHash.new { KeyTransformerHash.new { |value| yield value } }
      @sticky = Set.new
    end

    # Returns the object cached with the same class and key as the given value.
    # If this Cache has a factory but does not have an entry for value, then the
    # factory is called on the value to create a new entry. 
    def [](value)
      chash = @hash[value.class]
      cached = chash[value] if chash
      return cached unless cached.nil? and @factory
      obj = @factory.call(value) || return
      chash[value] = obj
    end
    
    # Adds the given value to this cache.
    def add(value)
      @hash[value.class][value] = value
    end

    # Clears the cache key => object hashes. If all is true, then every class hash
    # is cleared. Otherwise, only the non-sticky classes are cleared.
    def clear(all=false)
      if @sticky.empty? then
        @hash.clear
      else
        @hash.each { |klass, chash| chash.clear unless @sticky.include?(klass) }
      end
    end
  end
end