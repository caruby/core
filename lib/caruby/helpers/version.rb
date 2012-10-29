# A Version is an Array of version major and minor components that is comparable to
# another version identifier based on a precedence relationship.
class Version < Array
  include Comparable

  attr_reader :predecessor
  
  # Returns the given String as a Version.
  #
  # @example
  #   Version.parse("1.2.1alpha") #=> [1, 2, "1alpha"]
  def self.parse(s)
    components = s.split('.').map { |component| component =~ /[\D]/ ? component : component.to_i }
    Version.new(*components)
  end

  # Creates a new Version from the given version components and optional predecessor.
  #
  # @example
  #   prev = Version.new(1, 2, 2)
  #   Version.new(2, 1, 0, prev) > prev #=> true
  def initialize(*params)
    @predecessor = params.pop if self.class === params.last
    super(params)
  end

  # Returns the comparison of this version identifier to the other version identifier as follows:
  # * if this version can be compared to other via the predecessor graph, then return that comparison result
  # * otherwise, return a component-wise comparison
  #
  # @example
  #   beta = Version.new(1, 2, '1beta')
  #   Version.new(1, 2, 1, beta) > beta > #=> true
  #   Version.new(1, 2, 2) > beta #=> true
  #   Version.new(1, 2) < beta #=> true
  #   Version.new(2) > beta #=> true
  def <=>(other)
    return 0 if equal?(other)
    raise ArgumentError.new("Comparand is not a #{self.class}: #{other}") unless self.class === other
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
