module CaRuby
  # A GenericApplicationService wraps a common client caCORE application service.
  module UniformApplicationService
    # @return [Boolean] whether the caCORE version supports a generic application service
    def self.supported?
      begin
        !!Java::gov.nih.nci.system.client.ApplicationServiceProvider
      rescue NameError
        false
      end
    end
    
    # @param [String] :username the caTissue user name
    # @param [String] :password the caTissue user password
    # @raise [ArgumentError] if the username or password is missing
    def self.for(username, password)
      if password.nil? then raise ArgumentError.new('Cannot create the application service without a username') end
      if password.nil? then raise ArgumentError.new('Cannot create the application service without a password') end
      logger.debug { "Connecting to the application server with user #{username}..." }
      begin
        Java::gov.nih.nci.system.client.ApplicationServiceProvider.getApplicationService(username, password)
      rescue
        logger.error { "Connection to the application server with user #{username} and password #{password} was unsuccessful." }
        raise
      end
    end
  end
end
  