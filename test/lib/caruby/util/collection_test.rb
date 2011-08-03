$:.unshift 'lib'

require "test/unit"
require 'caruby/util/collection'

class CollectionTest < Test::Unit::TestCase
  def test_collection_classifier
    assert([].collection?, "array is not a collecton")
    assert(!nil.collection?, "nil is a collecton")
    assert(!'a'.collection?, "String is a collecton")
  end

  def test_hashify
    actual = [1, 2, 3].hashify { |key| key + 1 unless key == 2 }
    expected = {1 => 2, 2 => nil, 3 => 4}
    assert_equal(expected, actual, 'Hashify result incorrect')
  end

  def test_to_compact_hash
    actual = [1, 2, 3].to_compact_hash { |key| key + 1 unless key == 2 }
    expected = {1 => 2, 3 => 4}
    assert_equal(expected, actual, 'Compact hash incorrect')
  end
  
  def test_lazy_hash
    hash = LazyHash.new { |n| n * 2 }
    assert_equal(2, hash[1], "Lazy hash value incorrect")
    hash.merge!(2 => 3)
    assert_equal({1 => 2, 2 => 3}, hash, "Lazy hash merge incorrect")
  end

  def test_array_operator_set_argument
    array = [1, 2, 3]
    set = [3, 4].to_set
    assert_equal([3], array & set, "Array | Set result incorrect")
    assert_equal([1, 2, 3, 4], array | set, "Array | Set result incorrect")
    assert_equal([1, 2], array - set, "Array - Set result incorrect")
  end

  def test_empty_hash
    assert_raises(NotImplementedError, "Assigment to empty hash succeeds") { Hash::EMPTY_HASH[:a] = 2 }
  end

  def test_set_first
    assert_equal(1, [1, 2].to_set.first, "first of set incorrect")
    assert_nil(Set.new.first, "first of empty set incorrect")
  end

  def test_assoc_values_single
    expected = {:a => [1, 3], :b => [2, nil], :c => [nil, 4]}
    actual = {:a => 1, :b => 2}.assoc_values({:a => 3, :c => 4})
    assert_equal(expected, actual, "Association hash incorrect")
  end

  def test_assoc_values_multiple
    expected = {:a => [1, 3, 4], :b => [2, nil, 5]}
    actual = {:a => 1, :b => 2}.assoc_values({:a => 3}, { :a => 4, :b => 5 })
    assert_equal(expected, actual, "Multiple association hash incorrect")
  end

  def test_detect_value
   assert_equal(4, [1, 2, 3].detect_value { |item| item * 2 if item > 1 }, "Detect value incorrect")
   assert_nil([1, 2, 3].detect_value { |item| item * 2 if item > 3 }, "Value incorrectly detected")
  end

  def test_detect_with_value
    assert_equal([2, 1], [1, 2].detect_with_value { |item| item / 2 if item % 2 == 0 }, "Detect with value incorrect")
  end

  def test_array_filter
    base = [1, 2, 3]
    filter = base.filter { |n| n != 2 }
    assert_equal([1, 3], filter.to_a, 'Filter incorrect')
    base << 4
    assert_equal([1, 3, 4], filter.to_a, 'Filter does not reflect operand modification')
    filter << 5
    assert_equal([1, 2, 3, 4, 5], base.to_a, 'Filter does not modify the base')
  end

  def test_array_filter_without_block
    assert_equal([1, 3], [1, nil, 3, false].filter.to_a, 'Filter incorrect')
  end

  def test_set_filter_include
    assert([1, 2, 3].to_set.filter { |n| n > 1 }.include?(2), 'Set filter include? incorrect')
    assert(false == [1, 2, 3].to_set.filter { |n| n > 1 }.include?(1), 'Set filter include? incorrect')
  end

  def test_union
    base = [1, 2]
    sum = base.union([4])
    assert_equal([1, 2, 4], sum.to_a, 'Enumerator union incorrect')
    assert(sum.include?(2), "Enumerator union missing first array element")
    assert(sum.include?(4), "Enumerator union missing second array element")
    base << 3
    assert_equal([1, 2, 3, 4], sum.to_a, 'Enumerator union does not reflect operand modification')
  end

  def test_intersection
    base = [1, 2, 3, 4]
    other = [3]
    intersection = base.intersect(other)
    assert_equal([3], intersection.to_a, 'Enumerator intersection incorrect')
    other << 4 << 5
    assert_equal([3, 4], intersection.to_a, 'Enumerator intersection does not reflect operand modification')
  end

  def test_difference
    base = [1, 2, 3]
    diff = base.difference([3])
    assert_equal([1, 2], diff.to_a, 'Enumerator subtraction incorrect')
    base << 4
    assert_equal([1, 2, 4], diff.to_a, 'Enumerator subtraction does not reflect operand modification')
  end

  def test_wrap
    assert_equal([2, 4, 6], [1, 2, 3].wrap { |n| n * 2 }.to_a, 'Wrap incorrect')
  end

  def test_enum_addition
    a = [1, 2].filter { true }
    b = [3, 4].filter { true }
    ab = a + b
    assert_equal([1, 2, 3, 4], ab.to_a, "Composite array incorrect")
    a << 3
    assert_equal([1, 2, 3, 3, 4], ab.to_a, "Addition does not reflect change to first enumerable")
    b << 5
    assert_equal([1, 2, 3, 3, 4, 5], ab.to_a, "Addition does not reflect change to second enumerable")
  end
  
  def test_partial_sort
    sorted = [Array, Object, Numeric, Enumerable, Set].partial_sort
    assert(sorted.index(Array) < sorted.index(Enumerable), "Partial sort order incorrect")
    assert(sorted.index(Set) < sorted.index(Enumerable), "Partial sort order incorrect")
  end

  def test_hash_union
    a = {:a => 1, :b => 2}
    b = {:b => 3, :c => 4}
    ab = a + b
    assert_equal({:a => 1, :b => 2, :c => 4}, ab.keys.to_compact_hash { |key| ab[key] }, "Hash union incorrect")
    assert_equal([1, 2, 4], ab.values.sort, "Hash union values incorrect")
    a.delete(:b)
    assert_equal({:a => 1, :b => 3, :c => 4}, ab.keys.to_compact_hash { |key| ab[key] }, "Hash union does not reflect underlying change")
  end

  def test_hash_compose
    x = {:a => :c, :b => :d}
    y = {:c => 1}
    xy = x.compose(y)
    assert_equal({:a => {:c => 1}}, xy.keys.to_compact_hash { |key| xy[key] }, "Composed hash incorrect")
    y[:d] = 2
    assert_equal({:a => {:c => 1}, :b => {:d => 2}}, xy.keys.to_compact_hash { |key| xy[key] }, "Composed hash does not reflect underlying change")
  end

  def test_hash_join
    x = {:a => :c, :b => :d}
    y = {:c => 1}
    xy = x.join(y)
    assert_equal({:a => 1}, xy.keys.to_compact_hash { |key| xy[key] }, "Joined hash incorrect")
    y[:d] = 2
    assert_equal({:a => 1, :b => 2}, xy.keys.to_compact_hash { |key| xy[key] }, "Joined hash does not reflect underlying change")
  end
  
  def test_hash_diff
    x = {:a => 1, :b => 2, :c => 3}
    y = {:b => 2, :c => 4, :d => 5}
    assert_equal({:a => [1,nil], :c => [3,4], :d => [nil,5]}, x.diff(y), "Hash diff incorrect")
  end

  def test_to_assoc_hash
    actual = [[:a, 1], [:b, 2, 3], [:c], []].to_assoc_hash
    expected = {:a => 1, :b => [2,3], :c => nil}
    assert_equal(expected, actual, 'Association hash incorrect')
  end

  def test_hashable_equal
    assert_equal({:a => 1}, {:a => 1}.filter, "Hash equal incorrect")
  end

  def test_hash_enum_keys
    hash = { 1 => :a, 2 => :b }
    ek = hash.enum_keys
    assert_equal([1, 2], ek.sort, "Hash key enumerator incorrect")
    hash[3] = :c
    assert_equal([1, 2, 3], ek.sort, "Hash key enumerator does not reflect hash change")
  end

  def test_hash_enum_keys_with_value
    assert_equal([:b, :c], {:a => 1, :b => 2, :c => 2}.enum_keys_with_value(2).to_a, "Hash filtered value keys incorrect")
  end

  def test_hash_enum_keys_with_value_block
    assert_equal([:b, :c], {:a => 1, :b => 2, :c => 3}.enum_keys_with_value { |value| value > 1 }.to_a, "Hash filtered value block keys incorrect")
  end

  def test_hash_enum_values
    hash = { :a => 1, :b => 2 }
    ev = hash.enum_values
    assert_equal([1, 2], ev.sort, "Hash value enumerator incorrect")
    hash[:c] = 3
    assert_equal([1, 2, 3], ev.sort, "Hash value enumerator does not reflect hash change")
  end

  def test_hash_flatten
    assert_equal([:a, :b, :c, :d, :e, :f, :g], {:a => {:b => :c}, :d => :e, :f => [:g]}.flatten, "Hash flatten incorrect")
  end

  def test_hash_first
    assert_equal([:a, 1], {:a => 1, :b => 2}.first, "Hash first incorrect")
  end

  def test_hash_filter
    assert_equal({:a => 1, :c => 3}, {:a => 1, :b => 2, :c => 3}.filter { |k, v| k != :b }, "Hash filter incorrect")
  end

  def test_hash_sort
    assert_equal([['a', 1], ['b', 2]], {'a'=>1, 'b'=>2}.sort.to_a, "Hash sort incorrect")
  end
  
  def test_hash_sort_with_comparator
    assert_equal([[:a, 1], [:b, 2]], {:a => 1, :b => 2}.sort { |k1, k2| k1.to_s <=> k2.to_s }, "Hash sort with comparator incorrect")
  end

  def test_hash_default_filter
    assert_equal({:a => 1, :c => 3}, {:a => 1, :b => nil, :c => 3}.filter, "Hash default filter incorrect")
  end

  def test_hash_partition
    assert_equal([{:a => 1, :c => 3}, {:b => 2}], {:a => 1, :b => 2, :c => 3}.split { |k, v| k == :a or v == 3 }, "Hash partition incorrect")
  end

  def test_hash_filter_on_key
    filtered = {:a => 1, :b => 2, :c => 3}.filter_on_key { |k| k != :b }
    assert_equal({:a => 1, :c => 3}, filtered.to_hash, "Hash on key filter incorrect")
    assert_equal(1, filtered[:a], "Access on key filter inclusion incorrect")
    assert_nil(filtered[:b], "Access on key filter exclusion incorrect")
  end

  def test_hash_filter_on_value
    filtered = {:a => 1, :b => 2, :c => 3}.filter_on_value { |v| v != 2 }
    assert_equal({:a => 1, :c => 3}, filtered.to_hash, "Hash on value filter incorrect")
  end
  
  def test_hash_compact
    assert_equal({:a => 1, :c => 3}, {:a => 1, :b => nil, :c => 3}.compact.to_hash, "Compact hash incorrect")
  end

  def test_set_flatten
    inner = Set.new << :a
    actual = [inner, 'b'].flatten
    expected = [:a, 'b']
    assert_equal(expected, actual, 'Inner set not flattened')
  end

  def test_to_compact_hash
    assert_equal({1 => 2, 2 => 3}, [1, 2].to_compact_hash { |item| item + 1 }, 'to_compact_hash result incorrect')
  end

  def test_to_compact_hash_with_index
    assert_equal({:a => 1, :b => 2}, [:a, :b].to_compact_hash_with_index { |item, index| index + 1 }, 'to_compact_hash_with_index result incorrect')
  end

  def test_to_compact_hash_reject_missing
    assert_equal({1 => 2, 2 => 3}, [1, 2, 3].to_compact_hash { |item| item + 1 unless item > 2 }, 'to_compact_hash maps a key with a nil value')
  end

  def test_series
    actual = [1, 2, 3].to_series
    assert_equal('1, 2 and 3', actual, 'Print string incorrect')
  end

  def test_empty_series
    actual = [].to_series
    assert_equal('', actual, 'Print string incorrect')
  end

  def test_singleton_series
    actual = [1].to_series
    assert_equal('1', actual, 'Print string incorrect')
  end

  def test_copy_recursive
    hash = {1 => { 2 => 3 }, 4 => 5 }
    copy = hash.copy_recursive
    assert_equal(hash, copy, 'Copy not equal')
    hash[1][2] = 6
    assert_equal(3, copy[1][2], 'Copy reflects change to original')
    hash[4] = 7
    assert_equal(5, copy[4], 'Copy reflects change to original')
  end

  def test_case_insensitive_hash
    hash = CaseInsensitiveHash.new
    hash[:UP] = :down
    assert_equal(:down, hash['up'], "Case-insensitive hash look-up incorrect")
  end

  def test_transformed_hash
    hash = {:a => 1, :b => 2}
    xfm = hash.transform { |value| value * 2 }
    assert_equal(2, xfm[:a], 'Transformed hash accessor incorrect')
    assert_equal([2, 4], xfm.values.sort, 'Transformed hash values incorrect')
    assert(xfm.has_value?(4), 'Transformed hash value query incorrect')
    assert(!xfm.has_value?(1), 'Transformed hash value query incorrect')
    # base hash should be reflected in transformed hash
    hash[:b] = 3; hash[:c] = 4
    assert_equal(6, xfm[:b], 'Transformed hash does not reflect base hash change')
    assert_equal(8, xfm[:c], 'Transformed hash does not reflect base hash change')
  end

  def test_key_transformer_hash
    hash = KeyTransformerHash.new { |key| key % 2 }
    hash[1] = :a
    assert_equal(:a, hash[1], 'Key transformer hash entered value not found')
    assert_nil(hash[2], 'Transformed hash unentered value found')
    assert_equal(:a, hash[3], 'Key transformer hash equivalent value not found')
  end

  def test_hashinator
    base = {:a => 1, :b => 2}.to_a
    hash = Hashinator.new(base)
    assert_equal(base.to_set, hash.to_set, "Hashinator enumeration invalid")
    assert_equal(1, hash[:a], "Hashinator a value invalid")
    assert_equal(2, hash[:b], "Hashinator b value invalid")
    assert_nil(hash[:c], "Hashinator has association not in the base")
    base.first[1] = 3
    assert_equal(3, hash[:a], "Hashinator does not reflect change to underlying Enumerator")
    assert_equal(base, hash.to_hash.to_a, "Hashable to_hash incorrect")
  end

  def test_collector
    assert_equal([2, [3, 4]], Collector.on([1, [2, 3]]) { |n| n + 1 }, "Collector on nested array incorrect")
    assert_nil(Collector.on(nil) { |n| n + 1 }, "Collector on nil incorrect")
    assert_equal(2, Collector.on(1) { |n| n + 1 }, "Collector on non-collection incorrect")
  end

  def test_enumerate
    counter = 0
    nil.enumerate { |item| counter += item }
    assert_equal(0, counter, "Enumerate on nil incorrect")
    [1, 2, 3].enumerate { |item| counter += item }
    assert_equal(6, counter, "Enumerate on array incorrect")
    [1, [2, 3]].enumerate { |item| counter += 1 }
    assert_equal(8, counter, "Enumerate on nested array incorrect")
    2.enumerate { |item| counter += item }
    assert_equal(10, counter, "Enumerate on non-collection incorrect")
  end

  def test_to_enum
    assert_equal([], nil.to_enum.to_a, "to_enum on nil incorrect")
    assert_equal([1], 1.to_enum.to_a, "to_enum on non-collection incorrect")
    array = [1, 2]
    assert_same(array, array.to_enum, "to_enum on array incorrect")
    s = 'a'
    assert_same(s, s.to_enum, "to_enum on String incorrect")
  end

  def test_flattener
    assert_equal([1, 2, 3], Flattener.new([1, [2, 3]]).to_a, "Flattener on nested array incorrect")
    assert_equal([], Flattener.new(nil).to_a, "Flattener on nil incorrect")
    assert_equal([1], Flattener.new(1).to_a, "Flattener on non-collection incorrect")
    assert(Flattener.new(nil).all?, "Flattener all? on nil incorrect")
    assert_equal([:b, :c, :e], {:a => {:b => :c}, :d => [:e]}.enum_values.flatten.to_a, "Enumerable flatten incorrect")
  end

  def test_hash_flattener
    assert_equal([:a, :b, :c], {:a => {:b => :c}}.flatten.to_a, "Hash flatten incorrect")
    assert_equal([:b, :c, :e], {:a => {:b => :c}, :d => [:e]}.enum_values.flatten.to_a, "Enumerable flatten incorrect")
  end


  def test_conditional_enumerator
    assert_equal([1, 2], ConditionalEnumerator.new([1, 2, 3]) { |i| i < 3 }.to_a, "ConditionalEnumerator filter not applied")
  end

  def test_enumerable_size
   assert_equal(2, {:a => 1, :b => 2}.enum_keys.size, "Enumerable size incorrect")
  end

  def test_set_merge
    set = [1, 2].to_set
    merged = set.merge!([3])
    assert_equal([1, 2, 3].to_set, merged, "Merged set incorrect")
    assert_same(set, merged, "Set merge! did not return same set")
  end

  def test_set_add_all
    actual = [1, 2].add_all([3])
    expected = [1, 2, 3]
    assert_equal(expected, actual, 'Set content not added')
  end
end