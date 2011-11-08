require File.dirname(__FILE__) + '/../../helper'
require "test/unit"
require 'caruby/helpers/trie'

class TrieTest < Test::Unit::TestCase
  def test_trie
    trie = Trie.new
    assert_nil(trie[:a], "Non-existing node value incorrect")
    trie[:a, :b] = 1
    assert_nil(trie[:a], "Existing unvalued node value incorrect")
    assert_equal(1, trie[:a, :b], "Trie value incorrect")
  end
end