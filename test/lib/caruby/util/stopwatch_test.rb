require File.dirname(__FILE__) + '/../../helper'
require "test/unit"
require 'caruby/util/stopwatch'

class StopwatchTest < Test::Unit::TestCase
  def setup
    @timer = CaRuby::Stopwatch.new
  end
  
  def test_run
    t1 = @timer.run { 1000000.times { " " * 100 } }
    t2 = @timer.run { 1000000.times { " " * 100 } }
    assert_equal(t1.elapsed + t2.elapsed, @timer.elapsed, "Elapsed time incorrectly accumulated")
    assert_equal(t1.cpu + t2.cpu, @timer.cpu, "CPU time incorrectly accumulated")
  end
end