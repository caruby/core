require 'caruby/helpers/module'
require 'caruby/import/java'
require 'caruby/domain/java_attribute'

module CaRuby
  module Domain
    # Meta-data mix-in to infer attribute meta-data from Java properties.
    module Introspection
      
      protected
      
      # @return [Boolean] whether this {Resource} class meta-data has been introspected
      def introspected?
        # initialization sets the attribute => metadata hash
        !!@attr_md_hash
      end
  
      # Defines the Java property attribute and standard attribute methods, e.g.
      # +study_protocol+ and +studyProtocol+. A boolean attribute is provisioned
      # with an additional reader alias, e.g.  +available?+  for +is_available+.
      #
      # Each Java property attribute delegates to the Java property getter and setter.
      # Each standard attribute delegates to the Java property attribute.
      # Redefining these methods results in a call to the redefined method.
      # This contrasts with a Ruby alias, where the alias remains bound to the
      # original method body.
      def introspect
        # the module corresponding to the Java package of this class
        mod = parent_module
        # Set up the attribute data structures; delegates to Attributes.
        init_attributes
        logger.debug { "Introspecting #{qp} metadata..." }
        # The Java properties defined by this class with both a read and a write method.
        pds = java_properties(false)
        # Define the standard Java attribute methods.
        pds.each { |pd| define_java_attribute(pd) }
        logger.debug { "Introspection of #{qp} metadata complete." }
        self
      end
      
      private
  
      # Defines the Java property attribute and standard attribute methods, e.g.
      # +study_protocol+ and +studyProtocol+. A boolean attribute is provisioned
      # with an additional reader alias, e.g.  +available?+  for +is_available+.
      #
      # A standard attribute which differs from the property attribute delegates
      # to the property attribute, e.g. +study_protocol+ delegates to +studyProtocol+
      # rather than aliasing +setStudyProtocol+. Redefining these methods results
      # in a call to the redefined method.  This contrasts with a Ruby alias,
      # where each attribute alias is bound to the respective property reader or
      # writer.
      def define_java_attribute(pd)
        if transient?(pd) then
          logger.debug { "Ignoring #{name.demodulize} transient property #{pd.name}." }
          return
        end
        # the standard underscore lower-case attributes
        attr = create_java_attribute(pd)
        # delegate the standard attribute accessors to the property accessors
        alias_attribute_property(attr, pd.name)
        # add special wrappers
        wrap_java_attribute(attr, pd)
        # create Ruby alias for boolean, e.g. alias :empty? for :empty
        if pd.property_type.name[/\w+$/].downcase == 'boolean' then
          # strip leading is_, if any, before appending question mark
          aliaz = attr.to_s[/^(is_)?(\w+)/, 2] << '?'
          delegate_to_attribute(aliaz, attr)
        end
      end
  
      # Adds a filter to the attribute access method for the property descriptor pd if it is a String or Date.
      def wrap_java_attribute(attribute, pd)
        if pd.property_type == Java::JavaLang::String.java_class then
          wrap_java_string_attribute(attribute, pd)
        elsif pd.property_type == Java::JavaUtil::Date.java_class then
          wrap_java_date_attribute(attribute, pd)
        end
      end
  
      # Adds a to_s filter to this Class's String property access methods.
      def wrap_java_string_attribute(attribute, pd)
        # filter the attribute writer
        awtr = "#{attribute}=".to_sym
        pwtr = pd.write_method.name.to_sym
        define_method(awtr) do |value|
          stdval = value.to_s unless value.nil_or_empty?
          send(pwtr, stdval)
        end
        logger.debug { "Filtered #{qp} #{awtr} method with non-String -> String converter." }
      end
  
      # Adds a date parser filter to this Class's Date property access methods.
      def wrap_java_date_attribute(attribute, pd)
        # filter the attribute reader
        prdr = pd.read_method.name.to_sym
        define_method(attribute) do
          value = send(prdr)
          Java::JavaUtil::Date === value ? value.to_ruby_date : value
        end
        
        # filter the attribute writer
        awtr = "#{attribute}=".to_sym
        pwtr = pd.write_method.name.to_sym
        define_method(awtr) do |value|
          value = Java::JavaUtil::Date.from_ruby_date(value) if ::Date === value
          send(pwtr, value)
        end
  
        logger.debug { "Filtered #{qp} #{attribute} and #{awtr} methods with Java Date <-> Ruby Date converter." }
      end
  
      # Aliases the methods _aliaz_ and _aliaz=_ to _property_ and _property=_, resp.,
      # where _property_ is the Java property name for the attribute.
      def alias_attribute_property(aliaz, attribute)
        # strip the Java reader and writer is/get/set prefix and make a symbol
        prdr, pwtr = attribute_metadata(attribute).property_accessors
        alias_method(aliaz, prdr)
        writer = "#{aliaz}=".to_sym
        alias_method(writer, pwtr)
      end
  
      # Makes a standard attribute for the given property descriptor.
      # Adds a camelized Java-like alias to the standard attribute.
      #
      # @quirk caTissue DE annotation collection attributes are often misnamed,
      #   e.g. +histologic_grade+ for a +HistologicGrade+ collection attribute.
      #   This is fixed by adding a pluralized alias, e.g. +histologic_grades+.
      #
      # @return a new attribute symbol created for the given PropertyDescriptor pd
      def create_java_attribute(pd)
        # make the attribute metadata
        attr_md = JavaAttribute.new(pd, self)
        add_attribute_metadata(attr_md)
        # the property name is an alias for the standard attribute
        std_attr = attr_md.to_sym
        prop_attr = pd.name.to_sym
        delegate_to_attribute(prop_attr, std_attr) unless prop_attr == std_attr
        
        # alias a misnamed collection attribute, if necessary
        if attr_md.collection? then
          name = std_attr.to_s
          if name.singularize == name then
            aliaz = name.pluralize.to_sym
            if aliaz != name then
              logger.debug { "Adding annotation #{qp} alias #{aliaz} to the misnamed collection attribute #{std_attr}..." }
              delegate_to_attribute(aliaz, std_attr)
            end
          end
        end
  
        std_attr
      end
  
      # Defines methods _aliaz_ and _aliaz=_ which calls the standard _attribute_ and
      # _attribute=_ accessor methods, resp.
      # Calling rather than aliasing the attribute accessor allows the aliaz accessor to
      # reflect a change to the attribute accessor.
      def delegate_to_attribute(aliaz, attribute)
        if aliaz == attribute then CaRuby.fail(MetadataError, "Cannot delegate #{self} #{aliaz} to itself.") end
        rdr, wtr = attribute_metadata(attribute).accessors
        define_method(aliaz) { send(rdr) }
        define_method("#{aliaz}=".to_sym) { |value| send(wtr, value) }
        add_alias(aliaz, attribute)
      end
  
      # Makes a new synthetic attribute for each _method_ => _original_ hash entry.
      #
      # @param (see Class#offset_attr_accessor)
      def offset_attribute(hash, offset=nil)
        offset_attr_accessor(hash, offset)
        hash.each { |attr, original| add_attribute(attr, attribute_metadata(original).type) }
      end
    end
  end
end