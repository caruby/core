module CaRuby
  module JSON
    # {Jinx::Resource} => JSON serializer.
    module Serializer
      # @param args the JSON serialization options
      # @return [String] the JSON representation of this {Jinx::Resource}
      def to_json(*args)
        database.lazy_loader.disable do
          {
            'json_class' => json_class_name,
            'data' => json_value_hash
          }.to_json(*args)
        end
      end
      
      private
      
      # The JSON class name must be scoped by the Resource package module, not the
      # Java package, in order to recognize the Jinx::Resource JSON hooks.
      #
      # @return [String] the class name qualified by the Resource package module name context
      def json_class_name
        [self.class.domain_module, self.class.name.demodulize].join('::')
      end
      
      # Builds a serializable attribute => value hash. An independent or owner attribute
      # value is a copy of the referenced domain object consisting of only the key attributes.
      #
      # @return [{Symbol => Object}] the serializable value hash
      def json_value_hash
        vh = value_hash(self.class.nondomain_attributes)
        vh.merge!(value_hash(self.class.dependent_attributes))
        self.class.independent_attributes.each do |oa|
          value = send(oa) || next
          vh[oa] = owner.copy(owner.class.all_key_attributes)
        end
      end
      
      def json_independent_reference(ref)
        return ref.map { |item| json_independent_reference(item) } if ref.collection?
        ref.copy(json_foreign_key_value_hash(ref))
      end
      
      def json_foreign_key_value_hash(ref)
        json_key_value_hash(ref, ref.class.primary_key_attributes) or
        json_key_value_hash(ref, ref.class.secondary_key_attributes) or
        json_key_value_hash(ref, ref.class.alternate_key_attributes)
        Hash::EMPTY_HASH
      end
      
      def json_key_value_hash(ref, attributes)
        attributes.to_compact_hash { |ka| json_foreign_key_value(ref, ka) || return }
      end
      
      def json_foreign_key_value(ref, attribute)
        value = ref.send(attribute) || return
        Jinx::Resource === value ? json_foreign_key_value_hash(value) : value
      end
    end
  end
end

module Enumerable
  # @param args the JSON serialization options
  # @return [String] the JSON representation of this Enumerable as an array
  def to_json(*args)
    to_a.to_json(*args)
  end
end