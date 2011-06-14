require 'caruby/domain/metadata'

module CaRuby
  module Domain
    # Mixin extends a module to add meta-data to included classes.
    module Mixin
      # Adds {Metadata} to an included class.
      #
      # @example
      #   module CaRuby
      #     module Resource
      #       def self.included(mod)
      #         mod.extend(Domain::Mixin)
      #       end
      #     end
      #   end
      #   module ClinicalTrials
      #     module Resource
      #       include CaRuby::Resource
      #     end
      #     class Subject
      #       include Resource #=> introspects the Subject meta-data
      #     end
      #   end
      #
      # @param [Module] class_or_module the included module, usually a class
      def included(class_or_module)
        super
        if Class === class_or_module then
          Metadata.ensure_metadata_introspected(class_or_module)
        end
      end
    end
  end
end