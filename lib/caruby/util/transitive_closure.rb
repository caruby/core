require 'caruby/util/visitor'

class Object
  # Returns the transitive closure over a method or block, e.g.:
  #   class Node
  #     attr_reader :parent, :children
  #     def initialize(name, parent=nil)
  #       super()
  #       @name = name
  #       @parent = parent
  #       @children = []
  #       parent.children << self if parent
  #     end
  #
  #     def to_s;
  #   end
  #   a = Node.new('a'); b = Node.new('b', a), c = Node.new('c', a); d = Node.new('d', c)
  #   a.transitive_closure { |node| node.children }.to_a.join(", ") #=> a, b, c, d
  #   a.transitive_closure(:children).to_a.join(", ") #=> a, b, c, d
  # This method returns an array partially ordered by the closure method, i.e.
  # each node occurs before all other nodes referenced directly or indirectly by the closure method.
  #
  # If a method symbol or name is provided, then that method is called. Otherwise, the block is called.
  # In either case, the call is expected to return an object or Enumerable of objects which also respond
  # to the method or block.
  def transitive_closure(method=nil)
    raise ArgumentError.new("Missing both a method argument and a block") if method.nil? and not block_given?
    return transitive_closure() { |node| node.send(method) } if method
    CaRuby::Visitor.new(:depth_first) { |node| yield node }.to_enum(self).to_a.reverse
  end
end

module Enumerable
  # Returns the transitive closure over all items in this Enumerable.
  #
  # @see Object#transitive_closure
  def transitive_closure(method=nil, &navigator)
    # delegate to Object if there is a method argument
    return super(method, &navigator) if method
    # this Enumerable's children are this Enumerable's contents
    closure = super() { |node| node.equal?(self) ? self : yield(node) }
    # remove this collection from the closure
    closure[1..-1]
  end
end