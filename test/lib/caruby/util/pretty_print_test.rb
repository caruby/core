$:.unshift 'lib'

require "test/unit"

require 'set'
require 'date'
require 'caruby/util/pretty_print'

class PrettyPrintTest < Test::Unit::TestCase
  def test_nil
    assert_equal('nil', nil.pp_s, 'Nil pretty print incorrect')
  end

  def test_date_time
    date = DateTime.civil(2009, 4, 15, 5, 55, 55)
    assert_equal(date.strftime, date.pp_s, 'Date pretty print incorrect')
  end

  def test_array
    assert_equal('[:a, :b]', [:a, :b].pp_s, 'Array pretty print incorrect')
  end

  def test_java_collection
    a = Java::JavaUtil::ArrayList.new
    a << :a << :b
    assert_equal(a.to_a.pp_s, a.pp_s, 'Java collection pretty print incorrect')
  end

  def test_java_collection_cycle
    a = Java::JavaUtil::ArrayList.new
    a << :a << a
    assert_equal('[:a, [...]]', a.pp_s(:single_line), 'Cyclic set pretty print incorrect')
  end

  def test_hash
    assert_equal('{:a => a, :b => b}', {:a => 'a', :b => 'b'}.pp_s(:single_line), 'Hash pretty print incorrect')
  end

  def test_qp
    assert_equal('1', 1.qp, 'Numeric quick print incorrect')
    assert_equal('nil', nil.qp, 'nil quick print incorrect')
    assert_equal('a', 'a'.qp, 'String quick print incorrect')
    assert_equal(':a', :a.qp, 'Symbol quick print incorrect')
    assert_equal('[:a]', [:a].qp, 'Array quick print incorrect')
    assert_equal('TestCase', Test::Unit::TestCase.qp, 'Class quick print incorrect')
    
    x = {:a => 'a', :b => 'b'}
    x.qp
    
    
    assert_equal('{:a => a, :b => b}', {:a => 'a', :b => 'b'}.qp, 'Hash quick print incorrect')
  end

  def test_set
    assert_equal([:a].pp_s, [:a].to_set.pp_s, 'Set pretty print incorrect')
  end

  def test_set_cycle
    a = [:a].to_set
    a << a
    assert_equal('[:a, [...]]', a.pp_s(:single_line), 'Cyclic set pretty print incorrect')
  end

  def test_single_line_argument
    a = [].fill(:a, 0, 80)
    assert(a.pp_s =~ /\n/, 'Test array not long enough')
    assert(!a.pp_s(:single_line).include?("\n"), 'Single line option ignored')
  end

  def test_single_line_option
    a = [].fill(:a, 0, 80)
    assert_equal(a.pp_s(:single_line => true), a.pp_s(:single_line), 'Single line option ignored')
  end

  def test_print_wrapper_block
    tuples = [[:a, :b], [:c]]
    wrapper = PrintWrapper.new { |tuple| "<#{tuple.join(',')}>" }
    wrappers = tuples.wrap{ |tuple| wrapper.wrap(tuple) }
    assert_equal("[<a,b>, <c>]", wrappers.pp_s)
  end

  def test_wrapper_block
    assert_equal("[<a,b>, <c>]", [[:a, :b], [:c]].pp_s { |tuple| "<#{tuple.join(',')}>" })
  end
end