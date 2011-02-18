# A PartialOrder is a Comparable which restricted scope. Classes wich include PartialOrder
# are required to implement the <=> operator with the following semantics:
# *  _a_ <=> _b_ returns -1, 0, or 1 if a and b are comparable, nil otherwise
# A PartialOrder thus relaxes comparison symmetry, e.g.
#   a < b
# does not imply
#   b >= a.
# Example:
#   module Queued
#     attr_reader :queue
#     def <=>(other)
#       raise TypeError.new("Comparison argument is not another Queued item") unless Queued === other
#       queue.index(self) <=> queue.index(other) if queue.equal?(other.queue)
#     end
#   end
#   q1 = [a, b] # a, b are Queued
#   q2 = [c] # c is a Queued
#   a < b #=> true
#   b < c #=> nil
module PartialOrder
  include Comparable

  Comparable.instance_methods(false).each do |m|
    define_method(m.to_sym) do |other|
       self <=> other ? super : nil
    end

    # Returns true if other is an instance of this object's class and other == self,
    # false otherwise.
    def eql?(other)
      self.class === other and super
    end

    alias :== :eql?
  end
end