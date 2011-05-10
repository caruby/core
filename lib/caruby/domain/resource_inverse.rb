require 'caruby/import/java'
require 'caruby/domain/java_attribute_metadata'

module CaRuby
  # ResourceMetadata mix-in to infer and set inverse attributes.
  module ResourceInverse
    
    protected
    
    # Infers the inverse of the given attribute declared by this class. A domain attribute is
    # recognized as an inverse according to the {ResourceInverse#detect_inverse_attribute}
    # criterion.
    #
    # @param [AttributeMetadata] attr_md the attribute to check
    def infer_attribute_inverse(attr_md)
      inv = attr_md.type.detect_inverse_attribute(self)
      if inv then
        logger.debug { "Detected #{qp} #{attr_md} inverse #{inv.qp}." }
        set_attribute_inverse(attr_md.to_sym, inv)
      else
        logger.debug { "No inverse detected for #{qp} #{attr_md}." }
      end
    end
    
    # Sets the given bi-directional association attribute's inverse.
    #
    # @param [Symbol] attribute the subject attribute
    # @param [Symbol] the attribute inverse
    # @raise [TypeError] if the inverse type is incompatible with this Resource
    def set_attribute_inverse(attribute, inverse)
      attr_md = attribute_metadata(attribute)
      # return if inverse is already set
      return if attr_md.inverse == inverse
      # the default inverse
      inverse ||= attr_md.type.detect_inverse_attribute(self)
      # the inverse attribute meta-data
      inv_md = attr_md.type.attribute_metadata(inverse)
      # if the attribute is the many side of a 1:M relation, then delegate to the one side.
      if attr_md.collection? and not inv_md.collection? then
        return attr_md.type.set_attribute_inverse(inverse, attribute)
      end
      # this class must be the same as or a subclass of the inverse attribute type
      unless self <= inv_md.type then
        raise TypeError.new("Cannot set #{qp}.#{attribute} inverse to #{attr_md.type.qp}.#{attribute} with incompatible type #{inv_md.type.qp}")
      end

      # if the attribute is not declared by this class, then make a new attribute
      # metadata specialized for this class.
      unless attr_md.declarer == self then
        attr_md = attr_md.dup
        attr_md.declarer = self
        add_attribute_metadata(attribute, inverse)
        logger.debug { "Copied #{attr_md.declarer}.#{attribute} to #{qp} with restricted inverse return type #{qp}." }
      end
      # Set the inverse in the attribute metadata.
      attr_md.inverse = inverse

      # If attribute is the one side of a 1:M or non-reflexive 1:1 relation, then add the inverse updater.
      unless attr_md.collection? then
        add_inverse_updater(attribute, inverse)
        unless attr_md.type == inv_md.type or inv_md.collection? then
          attr_md.type.delegate_writer_to_inverse(inverse, attribute)
        end
      end
    end
    
    # Detects an unambiguous attribute which refers to the given referencing class.
    # If there is exactly one attribute with the given return type, then that attribute is chosen.
    # Otherwise, the attribute whose name matches the underscored referencing class name is chosen,
    # if any.
    #
    # @param [Class] klass the referencing class
    # @return [Symbol, nil] the inverse attribute for the given referencing class and inverse,
    #   or nil if no owner attribute was detected
    def detect_inverse_attribute(klass)
      # the candidate attributes which return the referencing type
      candidates = domain_attributes.compose { |attr_md| klass <= attr_md.type }
      attr = detect_inverse_attribute_from_candidates(klass, candidates)
      if attr then
        logger.debug { "#{qp} #{klass.qp} inverse attribute is #{attr}." }
      else
        logger.debug { "#{qp} #{klass.qp} inverse attribute was not detected." }
      end
      attr
    end
    
    # Redefines the attribute writer method to delegate to its inverse writer.
    # This is done to enforce inverse integrity.
    #
    # For a +Person+ attribute +account+ with inverse +holder+, this is equivalent to the following:
    #   class Person
    #     alias :set_account :account=
    #     def account=(acct)
    #       acct.holder = self if acct
    #       set_account(acct)
    #     end
    #   end
    def delegate_writer_to_inverse(attribute, inverse)
      attr_md = attribute_metadata(attribute)
      # nothing to do if no inverse
      inv_attr_md = attr_md.inverse_metadata || return
      logger.debug { "Delegating #{qp}.#{attribute} update to the inverse #{attr_md.type.qp}.#{inv_attr_md}..." }
      # redefine the write to set the dependent inverse
      redefine_method(attr_md.writer) do |old_writer|
        # delegate to the CaRuby::Resource set_inverse method
        lambda { |dep| set_inverse(dep, old_writer, inv_attr_md.writer) }
      end
    end

    private

    # @param klass (see #detect_inverse_attribute)
    # @param [<Symbol>] candidates the attributes constrained to the target type
    # @return (see #detect_inverse_attribute)
    def detect_inverse_attribute_from_candidates(klass, candidates)
      return if candidates.empty?
      # there can be at most one owner attribute per owner.
      return candidates.first.to_sym if candidates.size == 1
      # by convention, if more than one attribute references the owner type,
      # then the attribute named after the owner type is the owner attribute
      tgt = klass.name[/\w+$/].underscore.to_sym
      tgt if candidates.detect { |attr| attr == tgt }
    end
    
    # Modifies the given attribute writer method if necessary to update the given inverse_attr value.
    # This method is called on dependent and attributes qualified as inversible.
    #
    # @see #set_attribute_inverse
    def add_inverse_updater(attribute, inverse)
      attr_md = attribute_metadata(attribute)
      # the reader and writer methods
      rdr, wtr = attr_md.accessors
      logger.debug { "Injecting inverse #{inverse} updater into #{qp}.#{attribute} writer method #{wtr}..." }
      # the inverse atttribute metadata
      inv_attr_md = attr_md.inverse_metadata
      # the inverse attribute reader and writer
      inv_rdr, inv_wtr = inv_accessors = inv_attr_md.accessors

      # Redefine the writer method to update the inverse by delegating to the inverse
      redefine_method(wtr) do |old_wtr|
        # the attribute reader and (superseded) writer
        accessors = [rdr, old_wtr]
        if inv_attr_md.collection? then
          lambda { |other| add_to_inverse_collection(other, accessors, inv_rdr) }
        else
          lambda { |other| set_inversible_noncollection_attribute(other, accessors, inv_wtr) }
        end
      end
    end
  end
end