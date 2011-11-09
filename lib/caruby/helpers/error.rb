module CaRuby
  # Prints a log message and raises an exception.
  #
  # @param [Class] klass the error class to raise
  # @param [String] msg the error message
  # @param [Exception, nil] cause the exception which caused the error
  def self.fail(klass, msg, cause=nil)
    logger.error(msg)
    if cause then
      logger.error("Caused by: #{cause.class} - #{cause}\n#{cause.backtrace.pp_s}")
    end
    emsg = cause ? "#{msg} - #{$!}" : msg
    raise klass.new(emsg)
  end
end