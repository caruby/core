require 'jinx/migration/migratable'

module CaRuby
  # The Migratable mix-in adds migration support for CaRuby {Resource} domain objects.
  # This module augments the +Jinx::Migratable+ mix-in.
  module Migratable
    include Jinx::Migratable
                 
    # Overrides the default +Jinx::Migratable+ method to return this Resource's class
    # {Propertied#saved_independent_attributes}.
    #
    # @return the attributes to migrate
    def migratable_independent_attributes
      self.class.saved_independent_attributes
    end
  end
end
