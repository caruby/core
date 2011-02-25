require 'caruby/migration/migratable'
require 'caruby/domain/uniquify'

module CaRuby
  module Resource
    module Unique
      # Augments this {Unique} mix-in with a {Migratable#migrate} method which calls {Unique#uniquify}
      # to make this Resource object unique in the scope of its class.
      #
      # @param (see Migratable#migrate)
      def migrate(row, migrated)
        super
        logger.debug { "Migrator making #{self} unique..." }
        uniquify
      end
    end
  end
end