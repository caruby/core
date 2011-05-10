require 'caruby/util/validation'

module CaRuby
  # A Mergeable supports merging {Resource} attribute values.
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
    # this object. The default attributes is this mergeable's class
    # {ResourceAttributes#mergeable_attributes}.
    #
    # The merge is performed by calling {#merge_attribute} on each attribute with the matches
    # and merger block given to this method.
    #
    # @param [Mergeable, {Symbol => Object}] other the source domain object or value hash to merge from
    # @param [<Symbol>, nil] attributes the attributes to merge (default {ResourceAttributes#nondomain_attributes})
    # @param [{Resource => Resource}, nil] the optional merge source => target reference matches
    # @yield [attribute, oldval, newval] the optional merger block
    # @yieldparam [Symbol] attribute the merge target attribute
    # @yieldparam oldval the current merge attribute value
    # @yieldparam newval the new merge attribute value
    # @return [Mergeable] self
    # @raise [ArgumentError] if none of the following are true:
    #   * other is a Hash
    #   * attributes is non-nil
    #   * the other class responds to +mergeable_attributes+
    def merge_attributes(other, attributes=nil, matches=nil, &merger)
      return self if other.nil? or other.equal?(self)
      attributes = [attributes] if Symbol === attributes
      attributes ||= self.class.mergeable_attributes

      # if the source object is not a hash, then convert it to an attribute => value hash
      vh = Hashable === other ? other : other.value_hash(attributes)
      # merge the value hash
      vh.each { |attr, value| merge_attribute(attr, value, matches, &merger) }
      self
    end

    alias :merge :merge_attributes

    alias :merge! :merge
    
    # Merges the value newval into the attribute as follows:
    # * If the value is nil, empty or equal to the current attribute value, then no merge
    #   is performed.
    # * Otherwise, if a merger block is given to this method, then that block is called
    #   to perform the merge.
    # * Otherwise, if the attribute is a non-domain attribute and the current value is non-nil,
    #   then no merge is performed.
    # * Otherwise, if the attribute is a non-domain attribute and the current value is nil,
    #   then set the attribute to the newval.
    # * Otherwise, if the attribute is a domain non-collection attribute, then newval is recursively
    #   merged into the current referenced domain object.
    # * Otherwise, attribute is a domain collection attribute and matching newval members are
    #   merged into the corresponding current collection members and non-matching newval members
    #   are added to the current collection.
    #
    # @param [Symbol] attribute the merge attribute
    # @param newval the value to merge
    # @param [{Resource => Resource}, nil] the optional merge source => target reference matches
    # @yield (see #merge_attributes)
    # @yieldparam (see #merge_attributes)
    # @return the merged attribute value
    def merge_attribute(attribute, newval, matches=nil)
      # the previous value
      oldval = send(attribute)      
      # If nothing to merge or a block can take over, then bail. 
      if newval.nil? or mergeable__equal?(oldval, newval) then
        return oldval
      elsif block_given? then
        return yield(attribute, oldval, value)
      end
      
      # Discriminate between a domain and non-domain attribute.
      attr_md = self.class.attribute_metadata(attribute)
      if attr_md.domain? then
        merge_domain_attribute_value(attr_md, oldval, newval, matches)
      else
        merge_nondomain_attribute_value(attr_md, oldval, newval)
      end
    end

    private

    # @see #merge_attribute
    def merge_nondomain_attribute_value(attr_md, oldval, newval)
      if oldval.nil? then
        send(attr_md.writer, newval)
      elsif attr_md.collection? then
        oldval.merge(newval)
      else
        oldval
      end
    end
    
    # @see #merge_attribute
    def merge_domain_attribute_value(attr_md, oldval, newval, matches)
      # the dependent owner writer method, if any
      inv_md = attr_md.inverse_metadata
      if inv_md and not inv_md.collection? then
        owtr = inv_md.writer
      end

      # If the attribute is a collection, then merge the matches into the current attribute
      # collection value and add each unmatched source to the collection.
      # Otherwise, if the attribute is not yet set and there is a new value, then set it
      # to the new value match or the new value itself if unmatched.
      if attr_md.collection? then
        # TODO - refactor into method
        if oldval.nil? then
          raise ValidationError.new("Merge into #{qp} #{attr_md} with nil collection value is not supported")
        end
        # the references to add
        adds = []
        logger.debug { "Merging #{newval.qp} into #{qp} #{attr_md} #{oldval.qp}..." } unless newval.empty?
        newval.each do |src|
          # If the match target is in the current collection, then update the matched
          # target from the source.
          # Otherwise, if there is no match or the match is a new reference created
          # from the match, then add the match to the oldval collection.
          if matches && matches.has_key?(src) then
            # the source match
            tgt = matches[src]
            if tgt then
              if oldval.include?(tgt) then
                tgt.merge_attributes(src)
              else
                adds << tgt
              end
            end
          else
            adds << src
          end
        end
        # add the unmatched sources
        logger.debug { "Adding #{qp} #{attr_md} unmatched #{adds.qp}..." } unless adds.empty?
        adds.each do |ref|
          # If there is an owner writer attribute, then add the ref to the attribute collection by
          # delegating to the owner writer. Otherwise, add the ref to the attribute collection directly.
          owtr ? delegate_to_inverse_setter(attr_md, ref, owtr) : oldval << ref
        end
        oldval
      elsif newval.nil? then
        # no merge source
        oldval
      elsif oldval then
        # merge the source into the target
        oldval.merge(newval)
      else
        # No target; set the attribute to the source.
        # the target is either a source match or the source itself
        ref = matches[newval] if matches
        ref ||= newval
        logger.debug { "Setting #{qp} #{attr_md} reference #{ref.qp}..." }
        # If the target is a dependent, then set the dependent owner, which will in turn
        # set the attribute to the dependent. Otherwise, set the attribute to the target.
        owtr ? delegate_to_inverse_setter(attr_md, ref, owtr) : send(attr_md.writer, ref)
      end
      newval
    end

    # Java alert - Java TreeSet comparison uses the TreeSet comparator rather than an
    # element-wise comparator. Work around this rare aberration by converting the TreeSet
    # to a Ruby Set.
    def mergeable__equal?(v1, v2)
      Java::JavaUtil::TreeSet === v1 && Java::JavaUtil::TreeSet === v2 ? v1.to_set == v2.to_set : v1 == v2
    end
  end
end
