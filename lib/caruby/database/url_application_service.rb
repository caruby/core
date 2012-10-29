module CaRuby
  # An URLApplicationService wraps a legacy URL-based caCORE application service.
  class URLApplicationService
    # @quirk caCORE When more than one application service is used, then the remote
    #   instance must be reinitialized every time a different application service
    #   is used.
    #
    # @return the caCORE application service remote instance
    def self.for(url)
      # If the url differs from the current remote instance, then reinitialize.
      unless @url == url then
        @url = url
        logger.debug { "Connecting to service provider at #{@url}..." }
        @current = Java::gov.nih.nci.system.applicationservice.ApplicationServiceProvider.remote_instance(@url)
      end
      @current
    end
  end
end
  