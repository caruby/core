require 'caruby/helpers/collection'

module CaRuby
  # A WeakHash associates a key with a value until the key and value are no longer referenced elsewhere.
  #
  # The key and value must each be a jRuby wrapper for a Java object, i.e. a Ruby primitive such as String
  # or Integer, or an instance of a Java class imported into jRuby.
  class WeakHash
    include Hashable
    
    # Creates a new WeakHash.
    def initialize
      super
      @map = Java::JavaUtil::WeakHashMap.new
    end
    
    def each
      @map.each { |key, wref| yield(key, wref.get) }
    end

    # Returns the
    def [](key)
      # the weak reference mapped by the key
      wref = @map.get(key)
      # the referenced object
      wref.get if wref
    end

    def []=(key, value)
      # make a weak reference to the value
      wref = Java::JavaLangRef::WeakReference.new(value)
      # associate the object identifier with the weak reference
      @map.put(key, wref)
    end
  end
end
