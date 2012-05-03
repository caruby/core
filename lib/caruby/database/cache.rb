require 'jinx/helpers/lazy_hash'
require 'jinx/helpers/key_transformer_hash'

module CaRuby
  # Cache for objects held in memory and accessed by key.
  class Cache
    # The classes which are not cleared when {#clear} is called without the +all+ flag.
    attr_reader :sticky
    
    # @yield [item] returns the key for the given item to cache
    # @yieldparam item the object to cache
    def initialize
      # Make the class => {key => item} hash.
      # The {key => item} hash takes an item as an argument and converts
      # it to the key by calling the block given to this initializer.
      @ckh = Jinx::LazyHash.new do
        Jinx::KeyTransformerHash.new do |obj|
          yield(obj) || raise ArgumentError.new("The object to cache does not have a key: #{obj}")
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