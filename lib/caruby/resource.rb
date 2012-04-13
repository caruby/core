require 'caruby/importer'

module CaRuby
  # Augments +Jinx::Resource+ to inject {Propertied} persistence into introspected classes.
  # A CaRuby application domain module includes +Jinx::Resource+ and +CaRuby::Resource+.
  #
  # @example
  #   # The CaRuby application domain module
  #   module Domain
  #     include CaRuby::Resource, Jinx::Resource  
  #     # The caTissue Java package name.
  #     packages 'app.domain'
  #     # The JRuby mix-ins directory.
  #     definitions File.expand_path('domain', dirname(__FILE__))
  #   end
  module Resource
    def self.included(mod)
      super
      mod.extend(Importer)
    end
  end
end

      