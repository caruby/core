require 'logger'
require 'singleton'
require 'ftools'
require 'caruby/util/collection'

# @return [CaRuby::Logger] the global logger
def logger
  CaRuby::Log.instance.logger
end

module CaRuby
  # Extends the standard Logger to format multi-line messages on separate lines.
  class MultilineLogger < Logger
    # @see Logger#initialize
    def initialize(*args)
      super
    end
  
    private
  
    # Writes msg to the log device. Each line in msg is formatted separately.
    #
    # @param (see Logger#format_message)
    # @return (see Logger#format_message)
    def format_message(severity, datetime, progname, msg)
      if String === msg then
        msg.inject('') { |s, line| s << super(severity, datetime, progname, line.chomp) }
      else
        super
      end
    end
  end
  
  # Wraps a standard global Logger.
  class Log
    include Singleton
    
    # Opens the log.
    #
    # @param [String, IO, nil] file_or_dev the log file or device (default STDOUT)
    # @param [Hash, nil] the Logger::LogDevice options
    # @return [Logger] the logger
    def open(file_or_dev=nil, options=nil)
      dev = file_or_dev || default_log_file
      return @logger if same_file?(dev, @dev)
      # close the previous log file, if necessary
      @logger.close if @logger
      if String === dev then File.makedirs(File.dirname(dev)) end
      # default is 4-file rotation @ 16MB each
      shift_age = Options.get(:shift_age, options, 4)
      shift_size = Options.get(:shift_size, options, 16 * 1048576)
      @logger = MultilineLogger.new(dev, shift_age, shift_size)
      @logger.level = Options.get(:debug, options, ENV["DEBUG"]) ? Logger::DEBUG : Logger::INFO
      @logger.info('============================================')
      @logger.info('Logging started.')
      @dev = dev
      @logger
    end
  
    def close
      @logger.close
      @logger = nil
    end
  
    # Returns the logger.
    def logger
      @logger ||= open
    end
    
    # @return [String, nil] the log file, or nil if the log was opened on an IO rather
    #   than a String
    def file
      @dev if String === @dev
    end
    
    private
    
    def same_file?(f1, f2)
      f1 == f2 or (String === f2 and String === f1 and File.expand_path(f1) == File.expand_path(f2))
    end
    
    def default_log_file
      log_ndx = ARGV.index("--log") || ARGV.index("-l")
      if log_ndx then
        ARGV[log_ndx + 1]
      elsif ENV.has_key?("LOG") then
        ENV["LOG"]
      elsif defined?(DEF_LOG_FILE)
        DEF_LOG_FILE
      else
        'log/caruby.log'
      end
    end
  end
end