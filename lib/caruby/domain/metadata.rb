require 'caruby/util/collection'
require 'caruby/import/java'
require 'caruby/domain/java_attribute'
require 'caruby/domain/introspection'
require 'caruby/domain/inverse'
require 'caruby/domain/dependency'
require 'caruby/domain/attributes'
require 'caruby/json/deserializer'

module CaRuby
  module Domain
    # Exception raised if a meta-data setting is missing or invalid.
    class MetadataError < RuntimeError; end
    
    # Adds introspected metadata to a Class.
    module Metadata
      include Introspection, Inverse, Dependency, Attributes, JSON::Deserializer
      
      # @return [Module] the {Domain} module context
      attr_accessor :domain_module
      
      def self.extended(klass)
        super
        klass.class_eval do
          # Add this class's metadata.
          introspect
          # Add the {attribute=>value} argument constructor.
          class << self
            def new(opts=nil)
              obj = super()
              obj.merge_attributes(opts) if opts
              obj
            end
          end
        end
      end
  
      # @return the domain type for attribute, or nil if attribute is not a domain attribute
      def domain_type(attribute)
        attr_md = attribute_metadata(attribute)
        attr_md.type if attr_md.domain?
      end
  
      # Returns an empty value for the given attribute.
      # * If this class is not abstract, then the empty value is the initialized value.
      # * Otherwise, if the attribute is a Java primitive number then zero.
      # * Otherwise, if the attribute is a Java primitive boolean then +false+.
      # * Otherwise, the empty value is nil.
      #
      # @param [Symbol] attribute the target attribute
      # @return [Numeric, Boolean, Enumerable, nil] the empty attribute value
      def empty_value(attribute)
        if abstract? then
          attr_md = attribute_metadata(attribute)
          # the Java property type
          jtype = attr_md.property_descriptor.property_type if JavaAttribute === attr_md
          # A primitive is either a boolean or a number (String is not primitive).
          if jtype and jtype.primitive? then
            type.name == 'boolean' ? false : 0
          end
        else
          # Since this class is not abstract, create a prototype instance on demand and make
          # a copy of the initialized collection value from that instance.
          @prototype ||= new
          value = @prototype.send(attribute) || return
          value.class.new
        end
      end
      
     # Prints this classifier's content to the log.
      def pretty_print(q)
        # the Java property descriptors
        property_descriptors = java_attributes.wrap { |attr| attribute_metadata(attr).property_descriptor }
        # build a map of relevant display label => attributes
        prop_printer = property_descriptors.wrap { |pd| PROP_DESC_PRINTER.wrap(pd) }
        prop_syms = property_descriptors.map { |pd| pd.name.to_sym }.to_set
        aliases = @alias_std_attr_map.keys - attributes.to_a - prop_syms
        alias_attr_hash = aliases.to_compact_hash { |aliaz| @alias_std_attr_map[aliaz] }
        dependents_printer = dependent_attributes.wrap { |attr| DEPENDENT_ATTR_PRINTER.wrap(attribute_metadata(attr)) }
        owner_printer = owners.wrap { |type| TYPE_PRINTER.wrap(type) }
        inverses = @attributes.to_compact_hash do |attr|
           attr_md = attribute_metadata(attr)
           "#{attr_md.type.qp}.#{attr_md.inverse}" if attr_md.inverse
        end
        domain_attr_printer = domain_attributes.to_compact_hash { |attr| domain_type(attr).qp }
        map = {
          "Java properties" => prop_printer,
          "standard attributes" => attributes,
          "aliases to standard attributes" => alias_attr_hash,
          "secondary key" => secondary_key_attributes,
          "mandatory attributes" => mandatory_attributes,
          "domain attributes" => domain_attr_printer,
          "creatable domain attributes" => creatable_domain_attributes,
          "updatable domain attributes" => updatable_domain_attributes,
          "fetched domain attributes" => fetched_domain_attributes,
          "cascaded domain attributes" => cascaded_attributes,
          "owners" => owner_printer,
          "owner attributes" => owner_attributes,
          "inverse attributes" => inverses,
          "dependent attributes" => dependents_printer,
          "default values" => defaults
        }.delete_if { |key, value| value.nil_or_empty? }
        
        # one indented line per entry, all but the last line ending in a comma
        content = map.map { |label, value| "  #{label}=>#{format_print_value(value)}" }.join(",\n")
        # print the content to the log
        q.text("#{qp} structure:\n#{content}")
      end
  
      protected
  
      def self.extend_class(klass, mod)
        klass.extend(self)
        klass.add_metadata(mod)
      end
  
      private
      
      # A proc to print the unqualified class name.
      TYPE_PRINTER = PrintWrapper.new { |type| type.qp }
  
      DEPENDENT_ATTR_PRINTER = PrintWrapper.new do |attr_md|
        flags = []
        flags << :logical if attr_md.logical?
        flags << :autogenerated if attr_md.autogenerated?
        flags << :disjoint if attr_md.disjoint?
        flags.empty? ? "#{attr_md}" : "#{attr_md}(#{flags.join(',')})"
      end
  
      # A proc to print the property descriptor name.
      PROP_DESC_PRINTER = PrintWrapper.new { |pd| pd.name }

      def format_print_value(value)
        case value
          when String then value
          when Class then value.qp
          else value.pp_s(:single_line)
        end
      end
    end
  end
end