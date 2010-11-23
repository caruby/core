$:.unshift 'lib'

require 'caruby/util/stopwatch'
require "test/unit"

class StopwatchTest < Test::Unit::TestCase
  
  def setup
    @timer = Stopwatch.new
  end
  
  def test_run
    t1 = @timer.run { 1000000.times { " " * 100 } }
    t2 = @timer.run { 1000000.times { " " * 100 } }
    assert_equal(t1.elapsed + t2.elapsed, @timer.elapsed, "Elapsed time incorrectly accumulated")
    assert_equal(t1.cpu + t2.cpu, @timer.cpu, "CPU time incorrectly accumulated")
  end
end