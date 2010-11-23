require 'caruby/migration/migratable'
require 'caruby/domain/uniquify'

module CaRuby
  module Migratable
    # Unique makes a Migratable Resource domain object unique within the scope its class.
    module Unique
      include CaRuby::Resource::Unique
      
      # Augments the migration by making this Resource object unique in the scope of its class.
      #
      # @param (see CaRuby::Migratable#migrate)
      def migrate(row, migrated)
        super
        logger.debug { "Migrator making #{self} unique..." }
        uniquify
      end
    end
  end
end