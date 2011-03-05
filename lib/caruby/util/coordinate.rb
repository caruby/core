# JRuby alert - SyncEnumerator moved from generator to REXML in JRuby 1.5
require 'rexml/document'

# A Coordinate is a convenience Array wrapper class with aliased #x, #y and {#z} dimensions.
class Coordinate < Array
  include Comparable

  # @param [{Integer}] scalars the dimension coordinate values
  # @return a new Coordinate at the given scalars
  def initialize(*scalars)
    super(scalars)
  end

  # @return [Integer] the first dimension
  def x
    self[0]
  end

  # @param [Integer] the first dimension value
  def x=(value)
    self[0] = value
  end

  # @return [Integer, nil] the second dimension
  def y
    self[1]
  end

  # @param [Integer] the second dimension value
  def y=(value)
    self[1] = value
  end

  # @return [Integer, nil] the third dimension
  def z
    self[2]
  end

  # @param [Integer] the third dimension value
  def z=(value)
    self[2] = value
  end

  # @return [Boolean] whether other is a Coordinate and has the same content as this Coordinate
  def ==(other)
    super rescue false
  end

  # Returns the comparison of the highest dimension which differs from the other
  # coordinate, or zero if all dimensions are the same. This comparator sorts
  # coordinates in z-y-x order.
  # @example
  #   Coordinate.new(2, 1) < Coordinate.new(1, 2) #=> true
  # @return [Integer] the high-to-low dimension comparison
  # @raise [ArgumentError] if this Coordinate dimension size Coordinate differs from that
  #   of the other Dimension or any of the dimension values are nil
  # @raise [TypeError] if other is not a Coordinate
  def <=>(other)
    return true if equal?(other)
    raise TypeError.new("Can't compare #{self} with #{other} since it is not a Coordinate") unless Coordinate === other
    raise ArgumentError.new("Can't compare #{self} with #{other} since it has a different dimension count") unless size == other.size
    REXML::SyncEnumerator.new(self.reverse, other.reverse).each_with_index do |pair, index|
      dim = pair.first
      odim = pair.last
      raise ArgumentError.new("Can't compare #{self} with missing dimension #{index} to #{other}") unless dim
      raise ArgumentError.new("Can't compare #{self} to #{other} with missing dimension #{index}") unless odim
      cmp = dim <=> odim
      return cmp unless cmp.zero?
    end
    0
  end

  def to_s
    inspect
  end
end