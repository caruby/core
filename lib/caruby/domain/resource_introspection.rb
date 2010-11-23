require 'caruby/import/java'
require 'caruby/domain/java_attribute_metadata'

module CaRuby
  # ResourceMetadata mix-in to infer attribute meta-data from Java properties.
  module ResourceIntrospection

    private

    # Defines the Java property attribute and standard attribute methods, e.g.
    # +study_protocol+ and +studyProtocol+. A boolean attribute is provisioned
    # with an additional reader alias, e.g.  +available?+  for +is_available+.
    #
    # Each Java property attribute delegates to the Java property getter and setter.
    # Each standard attribute delegates to the Java property attribute.
    # Redefining these methods results in a call to the redefined method.
    # This contrasts with a Ruby alias, where the alias remains bound to the original method body.
    def introspect
      init_attributes # in ResourceAttributes
      logger.debug { "Introspecting #{qp} metadata..." }
      # filter properties for those with both a read and write method
      pds = java_properties(false)
      # define the standard Java attribute methods
      pds.each { |pd| define_java_attribute(pd) }
      logger.debug { "Introspection of #{qp} metadata complete." }
      self
    end

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
      if pd.propertyType == Java::JavaLang::String.java_class then
        wrap_java_string_attribute(attribute, pd)
      elsif pd.propertyType == Java::JavaUtil::Date.java_class then
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

    # Aliases the methods aliaz and _aliaz= to _property_ and _property=_, resp.,
    # where _property_ is the Java property name for the attribute.
    def alias_attribute_property(aliaz, attribute)
      # strip the Java reader and writer is/get/set prefix and make a symbol
      prdr, pwtr = attribute_metadata(attribute).property_accessors
      alias_method(aliaz, prdr)
      writer = "#{aliaz}=".to_sym
      alias_method(writer, pwtr)
    end

    # @return a new attribute symbol created for the given PropertyDescriptor pd
    def create_java_attribute(pd)
      # make the attribute metadata
      attr_md = JavaAttributeMetadata.new(pd, self)
      add_attribute_metadata(attr_md)
      # the property name is an alias for the standard attribute
      std_attr = attr_md.to_sym
      prop_attr = pd.name.to_sym
      delegate_to_attribute(prop_attr, std_attr) unless prop_attr == std_attr
      std_attr
    end

    # Defines methods _aliaz_ and _aliaz=_ which calls the standard _attribute_ and
    # _attribute=_ accessor methods, resp.
    # Calling rather than aliasing the attribute accessor allows the aliaz accessor to
    # reflect a change to the attribute accessor.
    def delegate_to_attribute(aliaz, attribute)
      rdr, wtr = attribute_metadata(attribute).accessors
      define_method(aliaz) { send(rdr) }
      define_method("#{aliaz}=".to_sym) { |value| send(wtr, value) }
      add_alias(aliaz, attribute)
    end

    # Modifies the given attribute writer method if necessary to update the given inverse_attr value.
    # This method is called on dependent and attributes qualified as inversible.
    #
    # @see ResourceDependency#add_owner
    # @see ResourceAttributes#set_attribute_inverse
    def add_inverse_updater(attribute, inverse)
      attr_md = attribute_metadata(attribute)
      # the reader and writer methods
      reader, writer = attr_md.accessors
      logger.debug { "Injecting inverse #{inverse} updater into #{qp}.#{attribute} writer method #{writer}..." }
      # the inverse atttribute metadata
      inv_attr_md = attr_md.inverse_attribute_metadata
      # the inverse attribute reader and writer
      inv_rdr, inv_wtr = inv_accessors = inv_attr_md.accessors
      # redefine the writer method to update the inverse
      # by delegating to the Resource instance set_inversible_attribute
      redefine_method(writer) do |old_wtr|
        # the attribute reader and (superseded) writer
        accessors = [reader, old_wtr]
        if inv_attr_md.collection? then
          lambda { |owner| add_to_inverse_collection(owner, accessors, inv_rdr) }
        else
          lambda { |owner| set_inversible_noncollection_attribute(owner, accessors, inv_wtr) }
        end
      end
    end
  end
end