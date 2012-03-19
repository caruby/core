# A Version is an Array of version major and minor components that is comparable to
# another version identifier based on a precedence relationship.
class Version < Array
  include Comparable

  attr_reader :predecessor

  # Creates a new Version from the given version components and optional predecessor.
  #
  # @example
  #   alpha = Version.new(1, '1alpha')
  #   Version.new(1, 1, alpha) > alpha #=> true
  def initialize(*params)
    @predecessor = params.pop if self.class === params.last
    super(params)
  end

  # Returns the comparison of this version identifier to the other version identifier as follows:
  # * if this version can be compared to other via the predecessor graph, then return that comparison result
  # * otherwise, return a component-wise comparison
  #
  # @example
  #   beta = Version.new(1, '1beta')
  #   Version.new(1) < beta > #=> true
  #   Version.new(1, 1) < beta #=> true
  #   Version.new(1, 1, beta) > beta #=> true
  def <=>(other)
    return 0 if equal?(other)
    Jinx.fail(ArgumentError, "Comparand is not a #{self.class}: #{other}") unless self.class === other
    return -1 if other.predecessor == self
    return 1 unless predecessor.nil? or predecessor < other
    each_with_index do |component, index|
      return 1 unless index < other.length
      other_component = other[index]
      if String === other_component then
        component = component.to_s
      elsif String === component
        other_component = other_component.to_s
      end
      cmp = (component <=> other_component)
      return cmp unless cmp.zero?
    end
    length < other.length ? -1 : 0
  end
end

class String
  # Returns this String as a Version.
  #
  # @example
  #   "1.2.1alpha".to_version #=> [1, 2, "1alpha"]
  def to_version
    components = split('.').map { |component| component =~ /[\D]/ ? component : component.to_i }
    Version.new(*components)
  end
end