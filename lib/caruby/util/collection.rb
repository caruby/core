require 'set'
require 'delegate'
require 'enumerator'
require 'caruby/util/class'
require 'caruby/util/validation'
require 'caruby/util/options'
require 'caruby/util/pretty_print'

class Object
  # Returns whether this object is a collection capable of holding heterogenous items.
  # An Object is a not a collection by default. Subclasses can override this method.
  def collection?
    false
  end
end

module Enumerable
  # Overrides {Object#collection?} to returns +true+, since an Enumerable is capable of
  # holding heterogenous items by default. Subclasses can override this method.
  def collection?
    true
  end
end

class String
  # Overrides {Enumerable#collection?} to returns +false+, since a String is constrained
  # to hold characters.
  def collection?
    false
  end
end

module Enumerable
  # Returns a new Hash generated from this Enumerable and an optional value generator block.
  # This Enumerable contains the Hash keys. If the value generator block is given to this
  # method then the block is called with each enumerated element as an argument to
  # generate the associated hash value. If no block is given, then the values are nil.
  #
  # @example
  #   [1, 2, 3].hashify { |item| item.modulo(2) } #=> { 1 => 1, 2 => 0, 3 => 1 }
  #   [:a].hashify #=> { :a => nil }
  # @return [Hash]
  def hashify
    hash = {}
    each { |item| hash[item] = yield item if block_given? }
    hash
  end
  
  # Returns a new Hash generated from this Enumerable and a required value generator block.
  # This Enumerable contains the Hash keys. The block is called with each enumerated
  # element as an argument to generate the associated hash value.
  # Only non-nil, non-empty values are included in the hash.
  #
  # @example
  #   [1, 2, 3].to_compact_hash { |item| item.modulo(2) } #=> { 1 => 1, 2 => 0, 3 => 1 }
  #   [1, 2, 3].to_compact_hash { |n| n.modulo(2) unless item > 2 } #=> {1 => 1, 2 => 0}
  #   [1, 2, 3].to_compact_hash { |n| n > 2 } #=> {1 => false, 2 => false, 3 => true}
  #   [1, 2, 3].to_compact_hash { |n| Array.new(n - 1, n) } #=> {2 => [2], 3 => [2, 3]}
  # @return [Hash]
  # @raise [ArgumentError] if the generator block is not given
  # @see #hashify
  def to_compact_hash
    raise ArgumentError.new("Compact hash builder is missing the value generator block") unless block_given?
    to_compact_hash_with_index { |item, index| yield item }
  end

  # Returns a new Hash generated from this Enumerable with a block whose arguments include the enumerated item
  # and its index. Every value which is nil or empty is excluded.
  #
  # @example
  #   [1, 2, 3].to_compact_hash_with_index { |item, index| item + index } #=> { 1 => 1, 2 => 3, 3 => 5 }
  # @yield [item, index] the hash value
  # @yieldparam item the enumerated value
  # @yieldparam index the enumeration index
  # @return [Hash] this {Enumerable} converted to a hash by the given block
  def to_compact_hash_with_index
    hash = {}
    self.each_with_index do |item, index|
      next if item.nil?
      value = yield(item, index)
      next if value.nil_or_empty?
      hash[item] = value
    end
    hash
  end

  # This method is functionally equivalent to +to_a.empty+ but is more concise and efficient.
  #
  # @return [Boolean] whether this Enumerable iterates over at least one item
  def empty?
    not any? { true }
  end

  # This method is functionally equivalent to +to_a.first+ but is more concise and efficient.
  #
  # @return the first enumerated item in this Enumerable, or nil if this Enumerable is empty
  def first
    detect { true }
  end

  # This method is functionally equivalent to +to_a.last+ but is more concise and efficient.
  #
  # @return the last enumerated item in this Enumerable, or nil if this Enumerable is empty
  def last
    detect { true }
  end

  # This method is functionally equivalent to +to_a.size+ but is more concise and efficient
  # for an Enumerable which does not implement the {#size} method.
  #
  # @return [Integer] the count of items enumerated in this Enumerable
  def size
    inject(0) { |size, item| size + 1 }
  end

  alias :length :size

  # @return [String] the content of this Enumerable as a series using {Array#to_series}
  def to_series(conjunction=nil)
    to_a.to_series
  end

  # Returns the first non-nil, non-false enumerated value resulting from a call to the block given to this method,
  # or nil if no value detected.
  #
  # @example
  #   [1, 2].detect_value { |item| item / 2 if item % 2 == 0 } #=> 1
  # @return [Object] the detected block result
  # @see #detect_with_value
  def detect_value
    each do |*item|
      value = yield(*item)
      return value if value
    end
    nil
  end

  # Returns the first item and value for which an enumeration on the block given to this method returns
  # a non-nil, non-false value.
  #
  # @example
  #   [1, 2].detect_with_value { |item| item / 2 if item % 2 == 0 } #=> [2, 1]
  # @return [(Object, Object)] the detected [item, value] pair
  # @see #detect_value
  def detect_with_value
    value = nil
    match = detect do |*item|
      value = yield(*item)
    end
    [match, value]
  end

  # Returns a new Enumerable that iterates over the base Enumerable items for which filter evaluates to a non-nil,
  #  non-false value, e.g.:
  #   [1, 2, 3].filter { |n| n != 2 }.to_a #=> [1, 3]
  #
  # Unlike select, filter reflects changes to the base Enumerable, e.g.:
  #   a = [1, 2, 3]
  #   filter = a.filter { |n| n != 2 }
  #   a << 4
  #   filter.to_a #=> [1, 3, 4]
  #
  # In addition, filter has a small, fixed storage requirement, making it preferable to select for large collections.
  # Note, however, that unlike select, filter does not return an Array.
  # The default filter block returns the passed item.
  #
  # @example
  #   [1, nil, 3].filter.to_a #=> [1, 3]
  # @yield [item] filter the selection filter
  # @yieldparam item the collection member to filter
  # @return [Enumerable] the filtered result
  def filter(&filter)
    Filter.new(self, &filter)
  end

  # @return an Enumerable which iterates over the non-nil items in this Enumerable
  def compact
    filter { |item| not item.nil? }
  end

  # Returns a new Flattener on this Enumerable, e.g.:
  #   {:a => {:b => :c}, :d => [:e]}.enum_values.flatten.to_a #=> [:b, :c, :e]
  #
  # @return [Enumerable] the flattened result
  def flatten
    Flattener.new(self).to_a
  end

  # Returns an Enumerable which iterates over items in this Enumerable and the other Enumerable in sequence, e.g.:
  #   [1, 2, 3] + [3, 4] #=> [1, 2, 3, 3, 4]
  #
  # Unlike the Array plus (+) operator, {#union} reflects changes to the underlying enumerators.
  #
  # @example
  #   a = [1, 2]
  #   b = [4, 5]
  #   ab = a.union(b)
  #   ab #=> [1, 2, 4, 5]
  #   a << 3
  #   ab #=> [1, 2, 3, 4, 5]
  # @param [Enumerable] other the Enumerable to compose with this Enumerable
  # @return [Enumerable] an enumerator over self followed by other
  def union(other)
    MultiEnumerator.new(self, other)
  end

  alias :+ :union

  # @return an Enumerable which iterates over items in this Enumerable but not the other Enumerable
  def difference(other)
    filter { |item| not other.include?(item) }
  end

  alias :- :difference

  # @return an Enumerable which iterates over items in this Enumerable which are also in the other Enumerable
  def intersect(other)
    filter { |item| other.include?(item) }
  end

  alias :& :intersect

  # Returns a new Enumerable that iterates over the base Enumerable applying the transformer block to each item, e.g.:
  #   [1, 2, 3].transform { |n| n * 2 }.to_a #=> [2, 4, 6]
  #
  # Unlike Array.map, {#wrap} reflects changes to the base Enumerable, e.g.:
  #   a = [2, 4, 6]
``#   transformed = a.wrap { |n| n * 2 }
  #   a << 4
  #   transformed.to_a #=> [2, 4, 6, 8]
  #
  # In addition, transform has a small, fixed storage requirement, making it preferable to select for large collections.
  # Note, however, that unlike map, transform does not return an Array.
  #
  # @yield [item] the transformer on the enumerated items
  # @yieldparam item an enumerated item
  # @return [Enumerable] an enumeration on the transformed values
  def transform(&mapper)
    Transformer.new(self, &mapper)
  end
  
  alias :wrap :transform
  
  def join(other)
    Joiner.new(self, other)
  end
  
  # Sorts this collection's members with a partial sort operator, i.e. the comparison returns -1, 0, 1 or nil.
  # The resulting sorted order places each non-nil comparable items in the sort order. The order of nil
  # comparison items is indeterminate.
  #
  # #example
  #    [Array, Numeric, Enumerable, Set].partial_sort #=> [Array, Numeric, Set, Enumerable]
  # @return [Enumerable] the items in this collection in partial sort order
  def partial_sort
    unless block_given? then return partial_sort { |item1, item2| item1 <=> item2 } end
    sort { |item1, item2| yield(item1, item2) or 1 }
  end
  
  # Sorts this collection's members with a partial sort operator on the results of applying the block.
  #
  # @return [Enumerable] the items in this collection in partial sort order
  def partial_sort_by
    partial_sort { |item1, item2| yield(item1) <=> yield(item2) }
  end
  
  # @yield [item] the transformer on the enumerated items
  # @yieldparam item an enumerated item
  # @return [Enumerable] the mapped values excluding null values
  def compact_map(&mapper)
    wrap(&mapper).compact
  end

  private

  # This Filter helper class applies a selection block to a base enumeration.
  class Filter
    include Enumerable

    def initialize(enum=[], &filter)
      @base = enum
      @filter = filter
    end

    # Calls the given block on each item which passes this Filter's filter test.
    #
    # @yield [item] the block called on each item
    # @yieldparam item the enumerated item
    def each
      @base.each { |item| yield(item) if @filter ? @filter.call(item) : item }
    end

    # Optimized for a Set base.
    #
    # @param [item] the item to check
    # @return [Boolean] whether the item is a member of this Enumerable
    def include?(item)
      return false if Set === @base and not @base.include?(item)
      super
    end

    # Adds an item to the base Enumerable, if this Filter's base supports it.
    #
    # @param item the item to add
    # @return [Filter] self
    def <<(item)
      @base << item
      self
    end

    # @param [Enumerable] other the Enumerable to merge
    # @return [Array] this Filter's filtered content merged with the other Enumerable
    def merge(other)
      to_a.merge!(other)
    end

    # Merges the other Enumerable into the base Enumerable, if the base supports it.
    #
    # @param other (see #merge)
    # @return [Filter, nil] this Filter's filtered content merged with the other Enumerable
    def merge!(other)
      @base.merge!(other)
      self
    end
  end

  # This Transformer helper class applies a transformer block to a base enumeration.
  class Transformer
    include Enumerable

    def initialize(enum=[], &transformer)
      @base = enum
      @xfm = transformer
    end

    # Sets the base Enumerable on which this Transformer operates and returns this transformer, e.g.:
    #  transformer = Transformer.new { |n| n * 2 }
    #  transformer.on([1, 2, 3]).to_a #=> [2, 4, 6]
    def on(enum)
      @base = enum
      self
    end

    # Calls the block on each item after this Transformer's transformer block is applied.
    def each
      @base.each { |item| yield(item.nil? ? nil : @xfm.call(item)) }
    end
  end

  # A MultiEnumerator iterates over several Enumerators in sequence. Unlike Array#+, MultiEnumerator reflects changes to the
  # underlying enumerators.
  #
  # @example
  #   a = [1, 2]
  #   b = [4, 5]
  #   ab = MultiEnumerator.new(a, b)
  #   ab.to_a #=> [1, 2, 4, 5]
  #   a << 3; b << 6; ab.to_a #=> [1, 2, 3, 4, 5, 6]
  class MultiEnumerator
    include Enumerable
    
    # @return [<Enumerable>] the enumerated collections
    attr_reader :components

    # Initializes a new {MultiEnumerator} on the given components.
    #
    # @param [<Enumerable>] the component enumerators to compose
    def initialize(*enums)
      super()
      @components = enums
      @components.compact!
    end

    # Iterates over each of this MultiEnumerator's Enumerators in sequence.
    def each
      @components.each { |enum| enum.each { |item| yield item  } }
    end
  end
end

# The Collector utility implements the {on} method to apply a block to a collection
# transitive closure.
module Collector
  # Collects the result of applying the given block to the given obj.
  # If obj is a collection, then collects the result of recursively calling this
  # Collector on the enumerated members.
  # If obj is nil, then returns nil.
  # Otherwise, calls block on obj and returns the result.
  #
  # @example
  #  Collector.on([1, 2, [3, 4]]) { |n| n * 2 } #=> [2, 4, [6, 8]]]
  #  Collector.on(nil) { |n| n * 2 } #=> nil
  #  Collector.on(1) { |n| n * 2 } #=> 2
  # @param obj the collection or item to enumerate
  def self.on(obj, &block)
    obj.collection? ? obj.map { |item| on(item, &block) } : yield(obj) unless obj.nil?
  end
end

class Object
  # Visits this object's enumerable content as follows:
  # * If this object is an Enumerable, then the block given to this method is called on each
  # item in this Enumerable.
  # * Otherwise, if this object is non-nil, then the the block is called on self.
  # * Otherwise, this object is nil and this method is a no-op.
  #
  # @yield [item] the block to apply to this object
  # @yieldparam item the enumerated items, or this object if it is non-nil and not an Enumerable 
  def enumerate(&block)
    Enumerable === self ? each(&block) : yield(self) unless nil?
  end

  # Returns an enumerator on this Object. This default implementation returns an Enumerable::Enumerator
  # on enumerate.
  #
  # @return [Enumerable] this object as an enumerable item
  def to_enum
    Enumerable::Enumerator.new(self, :enumerate)
  end
end

module Enumerable
  # @return self
  def to_enum
    self
  end
end

# A Flattener applies a given block to flattened collection content.
class Flattener
  include Enumerable

  # Visits the enumerated items in the given object's flattened content.
  # block is called on the base itself if the base is neither nil nor a Enumerable.
  # If the base object is nil or empty, then this method is a no-op and returns nil.
  def self.on(obj, &block)
    obj.collection? ? obj.each { |item| on(item, &block) } : yield(obj) unless obj.nil?
  end

  # Initializes a new Flattener on the given object.
  #
  # @param obj the Enumerable or non-collection object
  def initialize(obj)
    @base = obj
  end

  # Calls the the given block on this Flattener's flattened content.
  # If the base object is a collection, then the block is called on the flattened content.
  # If the base object is nil, then this method is a no-op.
  # If the base object is neither nil nor a collection, then the block given to this method
  # is called on the base object itself.
  #
  # @example
  #   Flattener.new(nil).each { |n| print n } #=>
  #   Flattener.new(1).each { |n| print n } #=> 1
  #   Flattener.new([1, [2, 3]]).each { |n| print n } #=> 123
  def each(&block)
    Flattener.on(@base, &block)
  end
end

# ConditionalEnumerator applies a filter to another Enumerable.
# @example
#   ConditionalEnumerator.new([1, 2, 3]) { |i| i < 3 }.to_a #=> [1, 2]
class ConditionalEnumerator
  include Enumerable

  # Creates a ConditionalEnumerator which wraps the base Enumerator with a conditional filter.
  def initialize(base, &filter)
    @base = base
    @filter = filter
  end

  # Applies the iterator block to each of this ConditionalEnumerator's base Enumerable items
  # for which this ConditionalEnumerator's filter returns true.
  def each
    @base.each { |item| (yield item) if @filter.call(item) }
  end
end

# Hashable is a Hash mixin that adds utility methods to a Hash.
# Hashable can be included by any class or module which implements an _each_ method
# with arguments _key_ and _value_.
module Hashable
  include Enumerable

  # @see Hash#each_pair
  def each_pair(&block)
    each(&block)
  end

  # @see Hash#[]
  def [](key)
    detect_value { |k, v| v if k == key }
  end

  # @see Hash#each_key
  def each_key
    each { |key, value| yield key }
  end

  # @yield [key] the detector block
  # @yieldparam key the hash key
  # @return [Object, nil] the key for which the detector block returns a non-nil, non-false value,
  #   or nil if none
  # @example
  #   {1 => :a, 2 => :b, 3 => :c}.detect_key { |k| k > 1 } #=> 2
  def detect_key
    each_key { |key| return key if yield key }
    nil
  end

  # @yield [value] the detector block
  # @yieldparam value the hash value
  # @return [Object, nil] the key for which the detector block returns a non-nil, non-false value,
  #   or nil if none
  # @example
  #   {:a => 1, :b => 2, :c => 3}.detect_key_with_value { |v| v > 1 } #=> :b
  def detect_key_with_value
    each { |key, value| return key if yield value }
    nil
  end

  # @see Hash#each_value
  def each_value
    each { |key, value| yield value }
  end

  # Returns a Hashable which composes each value in this Hashable with the key of
  # the other Hashable, e.g.:
  #   x = {:a => :c, :b => :d}
  #   y = {:c => 1}
  #   z = x.compose(y)
  #   z[:a] #=> {:c => 1}
  #   z[:b] #=> nil
  #
  # The accessor reflects changes to the underlying hashes, e.g. given the above example:
  #   x[:b] = 2
  #   z[:b] #=> {:c => 1}
  #
  # Update operations on the result are not supported.
  #
  # @param [Hashable] other the Hashable to compose with this Hashable
  # @return [Hashable] the composed result
  def compose(other)
    transform { |value| {value => other[value]} if other.has_key?(value) }
  end

  # Returns a Hashable which joins each value in this Hashable with the key of
  # the other Hashable, e.g.:
  #   x = {:a => :c, :b => :d}
  #   y = {:c => 1}
  #   z = x.join(y)
  #   z[:a] #=> 1
  #   z[:b] #=> nil
  #
  # The accessor reflects changes to the underlying hashes, e.g. given the above example:
  #   x[:b] = 2
  #   z[:b] #=> 2
  #
  # Update operations on the result are not supported.
  #
  # @param [Hashable] other the Hashable to join with this Hashable
  # @return [Hashable] the joined result
  def join(other)
    transform { |value| other[value] }
  end

  # Returns a Hashable which associates each key of both this Hashable and the other Hashable
  # with the corresponding value in the first Hashable which has that key, e.g.:
  #   x = {:a => 1, :b => 2}
  #   y = {:b => 3, :c => 4}
  #   z = x + y
  #   z[:b] #=> 2
  #
  # The accessor reflects changes to the underlying hashes, e.g. given the above example:
  #   x.delete(:b)
  #   z[:b] #=> 3
  #
  # Update operations on the result are not supported.
  #
  # @param [Hashable] other the Hashable to form a union with this Hashable
  # @return [Hashable] the union result
  def union(other)
    MultiHash.new(self, other)
  end

  alias :+ :union

  # Returns a new Hashable that iterates over the base Hashable <key, value> pairs for which the block
  # given to this method evaluates to a non-nil, non-false value, e.g.:
  #   {:a => 1, :b => 2, :c => 3}.filter { |k, v| k != :b }.to_hash #=> {:a => 1, :c => 3}
  #
  # The default filter block tests the value, e.g.:
  #   {:a => 1, :b => nil}.filter.to_hash #=> {:a => 1}
  #
  # @yield [key, value] the filter block
  # @return [Hashable] the filtered result
  def filter(&block)
    Filter.new(self, &block)
  end

  # Optimization of {#filter} for a block that only uses the key.
  #
  # @example
  #   {:a => 1, :b => 2, :c => 3}.filter_on_key { |k| k != :b }.to_hash #=> {:a => 1, :c => 3}
  #
  # @yield [key] the filter block
  # @yieldparam key the hash key to filter
  # @return [Hashable] the filtered result
  def filter_on_key(&block)
    KeyFilter.new(self, &block)
  end
  
  # @return [Hashable] a {#filter} that only uses the value.
  # @yield [value] the filter block
  # @yieldparam value the hash value to filter
  # @return [Hashable] the filtered result
  def filter_on_value
    filter { |key, value| yield value }
  end
  
  # @return [Hash] a {#filter} of this Hashable which excludes the entries with a null value
  def compact
    filter_on_value { |value| not value.nil? }
  end
  
  # Returns the difference between this Hashable and the other Hashable in a Hash of the form:
  #
  # _key_ => [_mine_, _theirs_]
  #
  # where:
  # * _key_ is the key of association which differs
  # * _mine_ is the value for _key_ in this hash 
  # * _theirs_ is the value for _key_ in the other hash 
  #
  # @param [Hashable] other the Hashable to subtract
  # @yield [key, v1, v2] the optional block which determines whether values differ (default is equality)
  # @yieldparam key the key for which values are compared
  # @yieldparam v1 the value for key from this Hashable
  # @yieldparam v2 the value for key from the other Hashable
  # @return [{Object => (Object,Object)}] a hash of the differences
  def diff(other)
    (keys.to_set + other.keys).to_compact_hash do |key|
       mine = self[key]
       yours = other[key]
       [mine, yours] unless block_given? ? yield(key, mine, yours) : mine == yours
    end
  end
  
  # @yield [key1, key2] the key sort block
  # @return a Hashable whose #each and {#each_pair} enumerations are sorted by key
  def sort(&sorter)
    SortedHash.new(self, &sorter)
  end

  # Returns a hash which associates each key in this hash with the value mapped by the others.
  #
  # @example
  #   {:a => 1, :b => 2}.assoc_values({:a => 3, :c => 4}) #=> {:a => [1, 3], :b => [2, nil], :c => [nil, 4]}
  #   {:a => 1, :b => 2}.assoc_values({:a => 3}, {:a => 4, :b => 5}) #=> {:a => [1, 3, 4], :b => [2, nil, 5]}
  #
  # @param [<Hashable>] others the other Hashables to associate with this Hashable
  # @return [Hash] the association hash
  def assoc_values(*others)
    all_keys = keys
    others.each { |hash| all_keys.concat(hash.keys) }
    all_keys.to_compact_hash do |key|
      others.map { |other| other[key] }.unshift(self[key])
    end
  end

  # Returns an Enumerable whose each block is called on each key which maps to a value which
  # either equals the given target_value or satisfies the filter block.
  #
  # @param target_value the filter value
  # @yield [value] the filter block
  # @return [Enumerable] the filtered keys
  def enum_keys_with_value(target_value=nil, &filter) # :yields: value
    return enum_keys_with_value { |value| value == target_value } if target_value
    filter_on_value(&filter).keys
  end

  # @return [Enumerable] Enumerable over this Hashable's keys
  def enum_keys
    Enumerable::Enumerator.new(self, :each_key)
  end

  # @return [Array] this Hashable's keys
  def keys
    enum_keys.to_a
  end

  # @param key search target
  # @return whether this Hashable has the given key
  def has_key?(key)
    enum_keys.include?(key)
  end

  alias :include? :has_key?

  # @return [Enumerable] an Enumerable over this Hashable's values
  def enum_values
    Enumerable::Enumerator.new(self, :each_value)
  end

  # @yield [key] the key selector
  # @return the keys which satisfy the block given to this method
  def select_keys(&block)
    enum_keys.select(&block)
  end
  
  # @yield [key] the key rejector
  # @return the keys which do not satisfy the block given to this method
  def reject_keys(&block)
    enum_keys.reject(&block)
  end
  
  # @yield [value] the value selector
  # @return the values which satisfy the block given to this method
  def select_values(&block)
    enum_values.select(&block)
  end
  
  # @yield [value] the value rejector
  # @return the values which do not satisfy the block given to this method
  def reject_values(&block)
    enum_values.reject(&block)
  end

  # @return [Array] this Enumerable's values
  def values
    enum_values.to_a
  end

  # @param value search target
  # @return whether this Hashable has the given value
  def has_value?(value)
    enum_values.include?(value)
  end

  # @return [Array] a flattened Array of this Hash
  # @example
  #   {:a => {:b => :c}, :d => :e, :f => [:g]} #=> [:a, :b, :c, :d, :e, :f, :g]
  def flatten
    Flattener.new(self).to_a
  end
  
  # @yield [key, value] hash splitter
  # @return [(Hash, Hash)] two hashes split by whether calling the block on the
  #   entry returns a non-nil, non-false value
  # @example
  #   {:a => 1, :b => 2}.split { |key, value| value < 2 } #=> [{:a => 1}, {:b => 2}]
  def split(&block)
    partition(&block).map { |pairs| pairs.to_assoc_hash }
  end

  # Returns a new Hash that recursively copies this hash's values. Values of type hash are copied using copy_recursive.
  # Other values are unchanged.
  #
  # This method is useful for preserving and restoring hash associations.
  #
  # @return [Hash] a deep copy of this Hashable 
  def copy_recursive
    copy = Hash.new
    keys.each do |key|
      value = self[key]
      copy[key] = Hash === value ? value.copy_recursive : value
    end
    copy
  end

  # @return [Hash] a new Hash that transforms each value
  # @example
  #   {:a => 1, :b => 2}.transform { |n| n * 2 }.values #=> [2, 4]
  def transform(&transformer)
    ValueTransformerHash.new(self, &transformer)
  end

  def to_hash
    inject({}) { |hash, pair| hash[pair.first] = pair.last; hash }
  end

  def to_set
    to_a.to_set
  end

  def to_s
    to_hash.to_s
  end

  def inspect
    to_hash.inspect
  end

  def ==(other)
    to_hash == other.to_hash rescue super
  end

  private

  # @see #filter
  class Filter
    include Hashable

    def initialize(base, &filter)
      @base = base
      @filter = filter
    end

    def each
      @base.each { |k, v| yield(k, v) if @filter ? @filter.call(k, v) : v }
    end
  end

  # @see #filter_on_key
  class KeyFilter < Filter
    include Hashable

    def initialize(base)
      super(base) { |k, v| yield(k) }
    end

    def [](key)
      super if @filter.call(key, nil)
    end
  end
  
  # @see #sort
  class SortedHash
    include Hashable
    
    def initialize(base, &comparator)
      @base = base
      @comparator = comparator
    end
    
    def each
      @base.keys.sort { |k1, k2| @comparator ? @comparator.call(k1, k2) : k1 <=> k2 }.each { |k| yield(k, @base[k]) }
    end
  end

  # Combines hashes. See Hash#+ for details.
  class MultiHash
    include Hashable
    
    # @return [<Hashable>] the enumerated hashes
    attr_reader :components

    def initialize(*hashes)
      if hashes.include?(nil) then raise ArgumentError.new("MultiHash is missing a component hash.") end
      @components = hashes
    end

    def [](key)
      @components.each { |hash| return hash[key] if hash.has_key?(key) }
      nil
    end

    def has_key?(key)
      @components.any? { |hash| hash.has_key?(key) }
    end

    def has_value?(value)
      @components.any? { |hash| hash.has_value?(value) }
    end

    def each
      @components.each_with_index do |hash, index|
        hash.each do |key, value|
           yield(key, value) unless (0...index).any? { |i| @components[i].has_key?(key) }
        end
      end
      self
    end
  end

  # The ValueTransformerHash class pipes the value from a base Hashable into a transformer block.
  class ValueTransformerHash
    include Hashable

    # Creates a ValueTransformerHash on the base hash and value transformer block.
    def initialize(base, &transformer) # :yields: value
      @base = base
      @xfm = transformer
    end

    # Returns the value at key after this ValueTransformerHash's transformer block is applied, or nil
    # if this hash does not contain key.
    def [](key)
      @xfm.call(@base[key]) if @base.has_key?(key)
    end

    def each
      @base.each { |key, value| yield(key, @xfm.call(value)) }
    end
  end
end

# The KeyTransformerHash class pipes the key access argument into a transformer block before
# accessing a base Hashable, e.g.:
#   hash = KeyTransformerHash.new { |key| key % 2 }
#   hash[1] = :a
#   hash[3] # => :a
class KeyTransformerHash
  include Hashable

  # Creates a KeyTransformerHash on the optional base hash and required key transformer block.
  #
  # Raises ArgumentError if there is no extractor block
  def initialize(base={}, &transformer) # :yields: key
    raise ArgumentError.new("Missing required Accessor block") unless block_given?
    @base = base
    @xfm = transformer
  end

  # Returns the value at key after this KeyTransformerHash's transformer block is applied to the key,
  # or nil if the base hash does not contain an association for the transforemd key.
  def [](key)
    @base[@xfm.call(key)]
  end

  # Sets the value at key after this KeyTransformerHash's transformer block is applied, or nil
  # if this hash does not contain an association for the transformed key.
  def []=(key, value)
    @base[@xfm.call(key)] = value
  end

  # Delegates to the base hash.
  # Note that this breaks the standard Hash contract, since
  #   all? { |k, v| self[k] }
  # is not necessarily true because the key is transformed on access.
  # @see Accessor for a KeyTransformerHash variant that restores this contract
  def each(&block)
    @base.each(&block)
  end
end

class Hash
  include Hashable

  # The EMPTY_HASH constant is an immutable empty hash, used primarily as a default argument.
  class << EMPTY_HASH = Hash.new
    def []=(key, value)
      raise NotImplementedError.new("Modification of the constant empty hash is not supported")
    end
  end
end

# Hashinator creates a Hashable from an Enumerable on [_key_, _value_] pairs.
# The Hashinator reflects changes to the underlying Enumerable.
#
# @example
#   base = [[:a, 1], [:b, 2]]
#   hash = Hashinator.new(base)
#   hash[:a] #=> 1
#   base.first[1] = 3
#   hash[:a] #=> 3
class Hashinator
  include Hashable

  def initialize(enum)
    @base = enum
  end

  def each
    @base.each { |pair| yield(*pair) }
  end
end

#
# A Hash that creates a new entry on demand.
#
class LazyHash < Hash
  #
  # Creates a new Hash with the specified value factory proc.
  # The factory proc has one argument, the key.
  # If access by key fails, then a new association is created
  # from the key to the result of calling the factory proc.
  #
  # Example:
  #   hash = LazyHash.new { |key| key.to_s }
  #   hash[1] = "1"
  #   hash[1] #=> "1"
  #   hash[2] #=> "2"
  #
  # If a block is not provided, then the default association value is nil, e.g.:
  #   hash = LazyHash.new
  #   hash.has_key?(1) #=> false
  #   hash[1] #=> nil
  #   hash.has_key?(1) #=> true
  #
  # A nil key always returns nil. There is no hash entry for nil, e.g.:
  #   hash = LazyHash.new { |key| key }
  #   hash[nil] #=> nil
  #   hash.has_key?(nil) #=> false
  #
  # If the :compact option is set, then an entry is not created
  # if the value initializer result is nil or empty, e.g.:
  #   hash = LazyHash.new { |n| 10.div(n) unless n.zero? }
  #   hash[0] #=> nil
  #   hash.has_key?(0) #=> false
  def initialize(options=nil)
    reject_flag = Options.get(:compact, options)
    # Make the hash with the factory block
    super() do |hash, key|
      if key then
        value = yield key if block_given?
        hash[key] = value unless reject_flag and value.nil_or_empty?
      end
    end
  end
end

class Array
  # The EMPTY_ARRAY constant is an immutable empty array, used primarily as a default argument.
  class << EMPTY_ARRAY = Array.new
    def <<(value)
      raise NotImplementedError.new("Modification of the constant empty array is not supported")
    end
  end

  # Relaxes the Ruby Array methods which take an Array argument to allow collection Enumerable arguments.
  [:|, :+, :-, :&].each do |meth|
    redefine_method(meth) do |old_meth|
      lambda { |other| send(old_meth, other.collection? ? other.to_a : other) }
    end
  end

  redefine_method(:flatten) do |old_meth|
    # if an item is a non-Array collection, then convert it into an array before recursively flattening the list
    lambda { map { |item| item.collection? ? item.to_a : item }.send(old_meth) }
  end

  # Returns an array containing all but the first item in this Array. This method is syntactic sugar for
  # +self[1..-1]+ or +last(length-1)+
  def rest
    self[1..-1]
  end

  # Prints the content of this array as a series, e.g.:
  #   [1, 2, 3].to_series #=> "1, 2 and 3"
  #   [1, 2, 3].to_series('or') #=> "1, 2 or 3"
  #
  # If a block is given to this method, then the block is applied before the series is formed, e.g.:
  #   [1, 2, 3].to_series { |n| n + 1 } #=> "2, 3 and 4"
  def to_series(conjunction=nil)
    conjunction ||= 'and'
    return map { |item| yield item }.to_series(conjunction) if block_given?
    padded_conjunction = " #{conjunction} "
    # join all but the last item as a comma-separated list and append the conjunction and last item
    length < 2 ? to_s : self[0...-1].join(', ') + padded_conjunction + last.to_s
  end

  # Returns a new Hash generated from this array of arrays by associating the first element of each
  # member to the remaining elements. If there are only two elements in the member, then the first
  # element is associated with the second element. If there is less than two elements in the member,
  # the first element is associated with nil. An empty array is ignored.
  #
  # @example
  #   [[:a, 1], [:b, 2, 3], [:c], []].to_assoc_hash #=> { :a => 1, :b => [2,3], :c => nil }
  # @return [Hash] the first => rest hash
  def to_assoc_hash
    hash = {}
    each do |item|
      raise ArgumentError.new("Array member must be an array: #{item.pp_s(:single_line)}") unless Array === item
      key = item.first
      if item.size < 2 then
        value = nil
      elsif item.size == 2 then
        value = item[1]
      else
        value = item[1..-1]
      end
      hash[key] = value unless key.nil?
    end
    hash
  end

  alias :base__flatten :flatten
  private :base__flatten
  # Recursively flattens this array, including any collection item that implements the +to_a+ method.
  def flatten
    # if any item is a Set or Java Collection, then convert those into arrays before recursively flattening the list
    if any? { |item| Set === item or Java::JavaUtil::Collection === item } then
      return map { |item| (Set === item or Java::JavaUtil::Collection === item) ? item.to_a : item }.flatten
    end
    base__flatten
  end

  # Concatenates the other Enumerable to this array.
  #
  # @param [#to_a] other the other Enumerable
  # @raise [ArgumentError] if other does not respond to the +to_a+ method
  def add_all(other)
    return concat(other) if Array === other
    begin
      add_all(other.to_a)
    rescue NoMethodError
      raise
    rescue
      raise ArgumentError.new("Can't convert #{other.class.name} to array")
    end
  end

  alias :merge! :add_all
end

# CaseInsensitiveHash accesses entries in a case-insensitive String comparison. The accessor method
# key argument is converted to a String before look-up.
#
# @example
#   hash = CaseInsensitiveHash.new
#   hash[:UP] = "down"
#   hash['up'] #=> "down"
class CaseInsensitiveHash < Hash
  def initialize
    super
  end

  def [](key)
    # if there is lower-case key association, then convert to lower-case and return.
    # otherwise, delegate to super with the call argument unchanged. this ensures
    # that a default block passed to the constructor will be called with the correct
    # key argument.
    has_key?(key) ? super(key.to_s.downcase) : super(key)
  end

  def []=(key, value)
    super(key.to_s.downcase, value)
  end

  def has_key?(key)
    super(key.to_s.downcase)
  end

  def delete(key)
    super(key.to_s.downcase)
  end

  alias :store :[]=
  alias :include? :has_key?
  alias :key? :has_key?
  alias :member? :has_key?
end

class Set
  # The standard Set {#merge} is an anomaly among Ruby collections, since merge modifies the called Set in-place rather
  # than return a new Set containing the merged contents. Preserve this unfortunate behavior, but partially address
  # the anomaly by adding the merge! alias for in-place merge.
  alias :merge! :merge
end
