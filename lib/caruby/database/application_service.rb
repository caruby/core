module CaRuby
  # An ApplicationService wraps a caCORE application service.
  class ApplicationService
    # @quirk caCORE When more than one application service is used, then the remote
    #   instance mustb e reinitialized every time a different application service
    #   is used.
    #
    # @param [String] the service URL
    # @return the caCORE application service remote instance
    def self.for(url)
      # Load the Java class on demand the first time this method is called.
      if @url.nil? then
        java_import Java::gov.nih.nci.system.applicationservice.ApplicationServiceProvider
      end
      # If the url differs from the current remote instance, then reinitialize.
      unless @url == url then
        @url = url
        logger.debug { "Connecting to service provider at #{@url}..." }
        @current = ApplicationServiceProvider.remote_instance(@url)
      end
      @current
    end
  end
end
  