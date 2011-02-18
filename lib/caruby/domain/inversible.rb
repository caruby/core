require 'caruby/util/log'
require 'caruby/database/persistable'
require 'caruby/util/pretty_print'

module CaRuby
  # {Resource} inverse integrity aspect mix-in.
  module Inversible
    # Sets an attribute inverse by calling the attribute writer method with the other argument.
    # If other is non-nil, then the inverse writer method is called on self.
    #
    # @param other [Resource] the attribute value to set
    # @param [Symbol] writer the attribute writer method
    # @param [Symbol] inv_writer the attribute inverse writer method defined for the other object
    def set_inverse(other, writer, inv_writer)
      other.send(inv_writer, self) if other
      send(writer, other)
    end
    
    # Sets a non-collection attribute value in a way which enforces inverse integrity.
    #
    # @param [Object] newval the value to set
    # @param [(Symbol, Symbol)] accessors the reader and writer methods to use in setting the
    #   attribute
    # @param [Symbol] inverse_writer the inverse attribute writer method
    def set_inversible_noncollection_attribute(newval, accessors, inverse_writer)
      rdr, wtr = accessors
      # the previous value
      oldval = send(rdr)
      # bail if no change
      return newval if newval.equal?(oldval)

      # clear the previous inverse
      logger.debug { "Moving #{qp} from #{oldval.qp} to #{newval.qp}..." } if oldval and newval
      if oldval then
        clr_wtr = self.class === oldval && oldval.send(rdr).equal?(self) ? wtr : inverse_writer
        oldval.send(clr_wtr, nil)
      end
      # call the writer
      send(wtr, newval)
      # call the inverse writer on self
      if newval then
        newval.send(inverse_writer, self)
        logger.debug { "Moved #{qp} from #{oldval.qp} to #{newval.qp}." } if oldval
      end
      
      newval
    end

    # Sets a collection attribute value in a way which enforces inverse integrity.
    # The inverse of the attribute is a collection accessed by calling inverse on newval.
    #
    # @param [Resource] newval the new attribute reference value
    # @param [(Symbol, Symbol)] accessors the reader and writer to use in setting
    #   the attribute
    # @param [Symbol] inverse the inverse collection attribute to which
    #   this domain object will be added
    # @yield a factory to create a new collection on demand (default is an Array)
    def add_to_inverse_collection(newval, accessors, inverse)
      rdr, wtr = accessors
      # the current inverse
      oldval = send(rdr)
      # no-op if no change
      return newval if oldval == newval

      # delete self from the current inverse reference collection
      if oldval then
        coll = oldval.send(inverse)
        coll.delete(self) if coll
      end

      # call the writer on this object
      send(wtr, newval)
      # add self to the inverse collection
      if newval then
        coll = newval.send(inverse)
        if coll.nil? then
          coll = block_given? ? yield : Array.new
          newval.set_attribute(inverse, coll)
        end
        coll << self
        if oldval then
          logger.debug { "Moved #{qp} from #{rdr} #{oldval.qp} #{inverse} to #{newval.qp}." }
        else
          logger.debug { "Added #{qp} to #{rdr} #{newval.qp} #{inverse}." }
        end
      end
      
      newval
    end
  end
end