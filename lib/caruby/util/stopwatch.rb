require 'benchmark'

module CaRuby
  # Stopwatch is a simple execution time accumulator.
  class Stopwatch
    # Time accumulates elapsed real time and total CPU time.
    class Time
      # @return [Benchmark::Tms] the Tms wrapped by this Time
      attr_reader :tms

      # @param [Benchmark::Tms, nil] the starting time (default is now)
      def initialize(tms=nil)
        @tms = tms || Benchmark::Tms.new
      end

      # @return [Numeric] the cumulative elapsed real clock time
      def elapsed
        @tms.real
      end

      #  @return [Numeric] the cumulative CPU total time
      def cpu
        @tms.total
      end

      # Adds the time to execute the given block to this time.
      #
      #  @return [Numeric] the split execution Time
      def split(&block)
        stms = Benchmark.measure(&block)
        @tms += stms
        Time.new(stms)
      end

      # Sets this benchmark timer to zero.
      def reset
        @tms = Benchmark::Tms.new
      end
    end
  
    # Executes the given block
    #
    # @return [Numeric] the execution Time
    def self.measure(&block)
      new.run(&block)
    end

    # Creates a new idle Stopwatch.
    def initialize
      @time = Time.new
    end

    # Executes the given block. Accumulates the execution time in this Stopwatch. 
    #
    #  @return [Numeric] the execution run Time
    def run(&block)
      @time.split(&block)
    end

    # @return [Numeric] the cumulative elapsed real clock time spent in {#run} executions
    def elapsed
      @time.elapsed
    end

    # @return [Numeric] the cumulative CPU total time spent in {#run} executions for the
    #  current process and its children
    def cpu
      @time.cpu
    end

    # Resets this Stopwatch's cumulative time to zero.
    def reset
      @time.reset
    end
  end
end