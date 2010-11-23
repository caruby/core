module CaRuby
  # A Mergeable supports merging attribute values.
  module Mergeable
    # Merges the values of the other attributes into this object and returns self.
    # The other argument can be either a Hash or an object whose class responds to the
    # +mergeable_attributes+ method.
    # The optional attributes argument can be either a single attribute symbol or a
    # collection of attribute symbols.
    #
    # A hash argument consists of attribute name => value associations.
    # For example, given a Mergeable +person+ object with attributes +ssn+ and +children+, the call:
    #   person.merge_attributes(:ssn => '555-55-5555', :children => children)
    # is equivalent to:
    #   person.ssn ||= '555-55-5555'
    #   person.children ||= []
    #   person.children.merge(children, :deep)
    # An unrecognized attribute is ignored.
    #
    # If other is not a Hash, then the other object's attributes values are merged into
    # this object. The default attributes is the intersection of this object's
    # mergeable attributes and the other object's mergeable attributes as determined by
    # {ResourceAttributes#mergeable_attributes}.
    #
    # #merge_attribute is called on each attribute with the merger block given to this
    # method.
    #
    # @param [Mergeable, {Symbol => Object}] other the source domain object or value hash to merge from
    # @param [<Symbol>, nil] attributes the attributes to merge (default {ResourceAttributes#nondomain_attributes})
    # @return [Mergeable] self
    # @raise [ArgumentError] if none of the following are true:
    #   * other is a Hash
    #   * attributes is non-nil
    #   * the other class responds to +mergeable_attributes+
    def merge_attributes(other, attributes=nil, &merger) # :yields: attribute, oldval, newval
      return self if other.nil? or other.equal?(self)
      attributes = [attributes] if Symbol === attributes
      attributes ||= self.class.mergeable_attributes

      # if the source object is not a hash, then convert it to an attribute => value hash
      vh = Hashable === other ? other : other.value_hash(attributes)
      # merge the value hash
      suspend_lazy_loader do
        vh.each { |attr, value| merge_attribute(attr, value, &merger) }
      end
      self
    end

    alias :merge :merge_attributes

    alias :merge! :merge

    # Merges value into attribute as follows:
    # * if the value is nil, empty or equal to the current attribute value, then no merge
    #   is performed
    # * otherwise, if the merger block is given to this method, then that block is called
    #   to perform the merge
    # * otherwise, if the current value responds to the merge! method, then that method
    #   is called recursively on the current value
    # * otherwise, if the current value is nil, then the attribute is set to value
    # * otherwise, no merge is performed
    #
    # Returns the merged value.
    def merge_attribute(attribute, value, &merger) # :yields: attribute, oldval, newval
      # the previous value
      oldval = send(attribute)

      # if nothing to merge, then return the unchanged previous value.
      # otherwise, if a merge block is given, then call it.
      # otherwise, if nothing to merge into then set the attribute to the new value.
      # otherwise, if the previous value is mergeable, then merge the new value into it.
      if value.nil_or_empty? or mergeable__equal?(oldval, value) then
        oldval
      elsif block_given? then
        yield(attribute, oldval, value)
      elsif oldval.nil? then
        send("#{attribute}=", value)
      elsif oldval.respond_to?(:merge!) then
        oldval.merge!(value)
      else
        oldval
      end
    end

    private

    # Fixes a rare Java TreeSet aberration: comparison uses the TreeSet comparator rather than an element-wise comparator.
    def mergeable__equal?(v1, v2)
      Java::JavaUtil::TreeSet === v1 && Java::JavaUtil::TreeSet === v2 ? v1.to_set == v2.to_set : v1 == v2
    end
  end
end
