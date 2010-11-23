require 'benchmark'

# Stopwatch is a simple execution time accumulator.
class Stopwatch
  # Time accumulates elapsed real time and total CPU time.
  class Time
    # The Benchmark::Tms wrapped by this Time.
    attr_reader :tms

    def initialize(tms=nil)
      @tms = tms || Benchmark::Tms.new
    end

    # Returns the cumulative elapsed real clock time.
    def elapsed
      @tms.real
    end

    # Returns the cumulative CPU total time.
    def cpu
      @tms.total
    end

    # Adds the time to execute the given block to this time. Returns the split execution Time.
    def split(&block)
      stms = Benchmark.measure(&block)
      @tms += stms
      Time.new(stms)
    end

    def reset
      @tms = Benchmark::Tms.new
    end
  end
  
  # Executes the given block. Returns the execution Time.
  def self.measure(&block)
    new.run(&block)
  end

  # Creates a new idle Stopwatch.
  def initialize
    @time = Time.new
  end

  # Executes the given block. Accumulates the execution time in this Stopwatch. 
  # Returns the execution Time.
  def run(&block)
    @time.split(&block)
  end

  # Returns the cumulative elapsed real clock time spent in {#run} executions.
  def elapsed
    @time.elapsed
  end

  # Returns the cumulative CPU total time spent in {#run} executions for the current process and its children.
  def cpu
    @time.cpu
  end

  # Resets this Stopwatch's cumulative time to zero.
  def reset
    @time.reset
  end
end