require 'caruby/util/properties'
require 'caruby/util/collection'
require 'caruby/util/options'

module CaRuby
  module Domain
    # CaRuby::Domain::Properties specializes the generic CaRuby::Properties class for domain properties.
    class Properties < CaRuby::Properties
      attr_reader :application

      # Creates a new Properties.
      #
      # Supported options include the CaRuby::Properties options as well as the following:
      # * :application - the application name
      #
      # The application name is used as a prefix for application-specific upper-case environment variables
      # and lower-case file names, e.g. +CATISSUE_USER+ for the +caTissue+ application login username
      # environment variable. The default application name is +caBIG+.
      #
      # The user properties file is always loaded if it exists. This file's name is a period followed by the
      # lower-case application name, located in the home directory, e.g. +~/.catissue.yaml+ for application
      # +caTissue+.
      def initialize(file=nil, options=nil)
        @application = Options.get(:application, options, "caBIG")
        super(file, options)
      end

      # Loads the properties in the following low-to-high precedence order:
      # * the home file +.+_application_+.yaml+, where _application_ is the application name
      # * the given property file
      # * the environment variables
      def load_properties(file)
        # canonicalize the file path
        file = File.expand_path(file)
        # load the home properties file, if it exists
        user_file = File.expand_path("~/.#{@application.downcase}.yaml")
        super(user_file) if user_file != file and File.exists?(user_file)
        # load the given file
        super(file)
        # the environment variables take precedence
        load_environment_properties
        # validate the required properties
        validate_properties
      end

      private

      # The application login userid environment variable.
      USER_ENV_VAR_SUFFIX = 'USER'

      # The application login password environment variable.
      PASSWORD_ENV_VAR_SUFFIX = 'PASSWORD'

      # The application service user property name.
      USER_PROP = :user

      # The application service password property name.
      PASSWORD_PROP = :password

      # The application Java jar location.
      PATH_PROP = :path

      def load_environment_properties
        user = ENV[user_env_var]
        if user then
          self[USER_PROP] = user
          logger.info("#{@application} login user obtained from environment property #{user_env_var} value '#{user}'.")
        end
        password = ENV[password_env_var]
        if password then
          self[PASSWORD_PROP] = password
          logger.info("#{@application} login password obtained from environment property #{password_env_var} value.")
        end
        path = ENV[path_env_var]
        if path then
          self[PATH_PROP] = path
          logger.info("#{@application} Java library path obtained from environment property #{path_env_var} value '#{path}'.")
        end
      end

      def user_env_var
        "#{@application}_#{USER_PROP}".upcase
      end

      def password_env_var
        "#{@application}_#{PASSWORD_PROP}".upcase
      end

      def path_env_var
        "#{@application}_#{PATH_PROP}".upcase
      end
    end
  end
end