require 'caruby/util/options'
require 'caruby/util/collection'

class Hash
  # Returns a new hash which merges the other hash with this hash.
  #
  # Supported options include the following:
  # * :deep - merge values which match on the key.
  # If the :deep option is set, and a key matches both this hash and the other hash
  # on hash values, then the other hash's value is recursively merged into this Hash's
  # value using the non-destructive {#merge} method with the deep option set.
  # If a block is given to this method, then the block is passed to the value merge.
  #
  # @example
  #   {:a => [1], :b => [2]}.merge({:b => [3]}, :deep) #=> {:a => [1], :b => [2, 3]}
  #   {:a => {:b => [1]}}.merge({:a => {:b => [2]}, :c => 3}, :deep) #=> {:a => {:b => [1, 2]}, :c => 3}
  def merge(other, options=nil, &block)
    dup.merge!(other, options, &block)
  end

  alias :base__merge! :merge!
  private :base__merge!

  # Merges the other hash into this hash and returns this modified hash.
  #
  # @see #merge the options and block description
  def merge!(other, options=nil, &block)
    # use the standard Hash merge unless the :deep option is set
    return base__merge!(other, &block) unless Options.get(:deep, options)
    # merge the other entries:
    # if the hash value is a hash, then call merge on that hash value.
    # otherwise, if the hash value understands merge, then call that method.
    # otherwise, if there is a block, then call the block.
    # otherwise, set the the hash value to the other value.
    base__merge!(other) do |key, oldval, newval|
      if Hash === oldval then
        oldval.merge(newval, options, &block)
      elsif oldval.respond_to?(:merge)
        oldval.merge(newval, &block)
      elsif block_given? then
        yield(key, oldval, newval)
      else
        newval
      end
    end
  end
end

class Array
  # Adds the elements in the other Enumerable which are not already included in this Array.
  # Returns this modified Array.
  def merge(other)
    # incompatible merge argument is allowed but ignored
    self unless Enumerable === other
    # concatenate the members of other not in self
    unique = other.to_a - self
    concat(unique)
  end
end