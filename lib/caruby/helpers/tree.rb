# A Tree consists of a root node and subtree children.
# A Tree can be decorated with an optional value.
class Tree
  attr_reader :root, :children

  attr_accessor :value

  # Creates a Trie with the given root node.
  def initialize(root=nil)
   @root = root
   @children = []
 end

  # Adds a subtree rooted at the given node as a child of this tree.
  def <<(node)
    @children << self.class.new(node)
    self
  end

  # Returns the subtree at the given node path.
  def subtree(*path)
    return self if path.empty?
    first = path.shift
    tree = @children.detect { |child| child.root == first }
    tree.subtree(*path) if tree
  end

  alias :[] :subtree

  # Creates the given node path if it does not yet exist.
  # Returns the subtree at the path.
  def fill(*path)
    return self if path.empty?
    first = path.shift
    tree = subtree(first)
    if tree.nil? then
      self << first
      tree = @children.last
    end
    tree.fill(*path)
  end

  def to_s
    root_s = @root.nil? || Symbol === root ? root.inspect : root.to_s
    return "[#{root_s}]" if @children.empty?
    "[#{root_s} -> #{@children.join(', ')}]"
  end
end