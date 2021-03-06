require 'jinx/resource'
require 'caruby/json/serializable'
require 'caruby/migration/migratable'
require 'caruby/database/persistable'

module CaRuby
  # Augments +Jinx::Resource+ to inject {Propertied} persistence into introspected classes.
  # A CaRuby application domain module includes +CaRuby::Resource+ and extends +CaRuby::Importer+.
  #
  # @example
  #   # The application domain module.
  #   module Domain
  #     # Add persistence to the domain instances.
  #     include CaRuby::Resource
  #     # Add introspection to this domain module.
  #     extend Jinx::Importer
  #     # Add persistence to the domain classes.
  #     @metadata_module = CaRuby::Metadata  
  #   end
  module Resource
    include CaRuby::Migratable, CaRuby::Persistable, CaRuby::JSON::Serializable, Jinx::Resource
  end
end

      