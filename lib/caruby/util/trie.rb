require File.join(File.dirname(__FILE__), 'tree')

# A Trie[http://en.wikipedia.org/wiki/Trie] is an associative access tree structure.
#
# @example
#   trie = Trie.new
#   trie[:a, :b] = 1
#   trie[:a, :b] #=> 1
#   trie[:a, :c] #=> nil
class Trie
  # Creates a new empty Trie.
  def initialize
    @tree = Tree.new
  end

  # @return the value at the given trie path
  def [](*path)
    tree = @tree[nil, *path]
    tree.value if tree
  end

  # @return the top_level Tree for this trie
  def to_tree
    @tree
  end

  # Sets the value for a node path.
  #
  # @example
  #   trie = Trie.new
  #   trie[:a, :b] = 1
  #   trie[:a, :b] #=> 1
  def []=(*path_and_value)
    value = path_and_value.pop
    @tree.fill(nil, *path_and_value).value = value
  end
end