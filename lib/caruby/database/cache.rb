require 'jinx/helpers/lazy_hash'
require 'jinx/helpers/associative'

module CaRuby
  # Cache for objects held in memory and accessed by key.
  class Cache
    # The classes which are not cleared when {#clear} is called.
    attr_reader :sticky
    
    # @yield [obj] returns the key for the given object to cache
    # @yieldparam obj the object to cache
    def initialize
      # Make the class => {object => {key => object}} hash.
      # The {object => {key => object}} hash is an Associative which converts the given
      # object to its key by calling the block given to this initializer.
      # The {{key => object} hash takes a key as an argument and returns the cached object.
      # If there is no cached object, then the object passed to the Associative is cached. 
      @ckh = Jinx::LazyHash.new do
        kh = Hash.new 
        # the obj => key associator
        assoc = Jinx::Associative.new do |obj|
          key = yield(obj)
          kh[key] if key
        end
        # the obj => key => value writer  
        assoc.writer do |obj, value|
          key = yield(obj)                                                                       
          raise ArgumentError.new("caRuby cannot cache object without a key: #{obj}") if key.nil?
          kh[key] = value
        end
      end
      @sticky = Set.new
    end

    # If there is already a cached object with the same key as the given item,
    # then this method returns that cached object. Otherwise, this method caches
    # the given item and returns that item.
    #
    # @param item the object to resolve
    # @return the object cached with the same class and key as the given item
    # @raise [ArgumentError] if the item does not have a key
    def [](item)
      @ckh[item.class][item]
    end
    
    # Adds the given item to this cache, unless one already exists.
    #
    # @param item the object to cache
    # @return the cached item
    def add(item)
      @ckh[item.class][item] ||= item
    end
    
    # Adds the given item to this cache. Overwrites an existing cache entry
    # for the given item's key, if one already exists.
    #
    # @param item the object to cache
    def add!(item)
      @ckh[item.class][item] = item
    end

    # Clears the non-sticky class caches.
    def clear
      if @sticky.empty? then
        @ckh.clear
      else
        @ckh.each { |klass, ch| ch.clear unless @sticky.include?(klass) }
      end
    end
  end
end