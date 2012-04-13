require 'caruby/metadata'

module CaRuby
  # Augments +Jinx::Importer+ to inject {Propertied} persistence into introspected classes.
  module Importer
    # Makes the introspected class persistable.
    #
    # @param [Class] klass the caTissue domain class
    def add_metadata(klass)
      super
      klass.extend(Metadata)
    end
  end
end
