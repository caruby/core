require 'logger'
require 'caruby/helpers/log'

module CaRuby
  module CLI
    # Extends the standard Logger::Application to use the {Log} and add start
    # functionality.
    class Application < Logger::Application
      # @param [String] appname the application name
      def initialize(appname=nil)
        super(appname)
        @log = Log::instance.logger
        @log.progname = @appname
        @level = @log.level
      end
      
      # Overrides Logger::Application start with the following enhancements:
      # * pass arguments and a block to the application run method
      # * improve the output messages
      # * print an exception to stderr as well as the log
      def start(*args, &block)
        # Adapted from Logger.
        status = 1
        begin
          log(INFO, "Starting #{@appname}...")
          status = run(*args, &block)
        rescue
          log(FATAL, "#{@appname} detected an exception: #{$!}\n#{$@.qp}")
          $stderr.puts "#{@appname} was unsuccessful: #{$!}.\nSee the log #{Log.instance.file} for more information."
        ensure
          log(INFO, "#{@appname} completed with status #{status}.")
        end
      end
    end
  end
end