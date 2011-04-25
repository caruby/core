require 'caruby/util/collection'
require 'caruby/util/validation'

# A DomainExtent contains class-specific key => object associations.
# The objects are created on demand and accessed by the get method.
#
# @example
#   DomainExtent.new { |klass, key| key.to_s + klass.name }.get(String, 'a') #=> aString
class DomainExtent < LazyHash
  # Creates a new DomainExtent. The block passed to the constructor
  # is a factory to create an object on demand, with arguments
  # the target class and the target key. The default block is empty.
  def initialize
    return initialize {} unless block_given?
    super { |klass| LazyHash.new { |key| yield klass, key } }
  end

  # Sets the factory used to create an instance of the specified class.
  # The factory is called to create a new instance when a get operation
  # does not yet have a key => instance association.
  #
  # The factory accepts a single argument, the instance key, e.g.
  #   set_factory(MyClass) { |key| MyClass.new(key) }
  def set_factory(klass, &factory)
    # the current instances, if any
    instances = fetch(klass) if has_key?(klass)
    # make the key => instance class extent map
    # the instance creation factory is
    class_extent = LazyHash.new { |key| yield key }
    # copy existing instances if necessary
    class_extent.merge!(instances) if instances
    # add the class => class extent association
    self[klass] = class_extent
  end

  # Returns the domain instance of the given class for the given key.
  # If there is nois no entry for key and the factory is set for the class,
  # then a new object is created on demand.
  def get(klass, key)
    raise RuntimeError.new("Invalid target class: #{klass}") unless klass.is_a?(Class)
    raise RuntimeError.new("Missing target key value") if key.nil?
    # the class extent hash is created on demand if necessary.
    # the instance is created on demand if there is a factory for the class.
    self[klass][key]
  end
end
