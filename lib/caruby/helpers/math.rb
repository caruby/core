# Extends the Numeric class with max and min methods. 
class Numeric
  # Returns the minimum of this Numeric and the other Numerics.
  def min(*others)
    others.inject(self) { |min, other| other < min ? other : min }
  end

  # Returns the minimum of this Numeric and the other Numerics.
  def max(*others)
    others.inject(self) { |max, other| other > max ? other : max }
  end
end