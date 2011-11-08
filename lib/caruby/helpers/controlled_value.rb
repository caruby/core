require 'set'

module CaRuby
  class ControlledValue
    attr_accessor :value, :parent

    attr_reader :children

    # Creates a new ControlledValue with the given String value and ControlledValue parent.
    # If parent is not nil, then the new CV is added to the parent's children.
    def initialize(value=nil, parent=nil)
      @value = value
      self.parent = parent
      @children = Set.new
    end

    def descendants
      children + children.map { |child| child.descendants.to_a }.flatten
    end

    def to_s
      value
    end

    private

    # Sets this CV's parent and adds this CV to the parent's children if necessary.
    def parent=(parent)
      @parent.children.delete(self) if @parent
      @parent = parent
      parent.children << self if parent
      parent
    end
  end
end
