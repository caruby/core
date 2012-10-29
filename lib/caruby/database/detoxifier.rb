require 'caruby/database/demangler'

module CaRuby
  class Database
    # The Detoxifier Database mix-in ensures that a caTissue query or save result is useable.
    #
    # @see {#detoxify}
    module Detoxifier
      def initialize
        super
        @demangler = Demangler.new
        @ftchd_vstr = Jinx::ReferenceVisitor.new() { |ref| ref.class.fetched_domain_attributes }
      end
      
      # Restores the integrity of a caCORE search or save result. This class works
      # around the caCORE problems described in {Demangler}.
      def demangle(toxic)
        @demangler.demangle(toxic)
      end
      
      # This method fixes the given toxic domain objects fetched from the database.
      #
      # Detoxification consists of the following:
      # * The fetched object's class might not have been previously referenced. In that
      #   case, introspect the fetched object's class.
      # * Clear toxic references that will result in a caCORE missing session error
      #   due to the caCORE API deficiency described below.
      # * Replaced fetched objects with the corresponding cached objects where possible.
      # * Set inverses to enforce inverse integrity where necessary.
      #
      # @quirk caCORE Dereferencing a caCORE search result uncascaded collection attribute
      #   raises a Hibernate missing session error. This bug is fixed by post-processing
      #   the +caCORE+ search result to set the toxic attributes to an empty value.
      #
      # @quirk caCORE The caCORE search result does not set the obvious inverse attributes,
      #   e.g. children fetched with a parent do not have the children inverse parent attribute
      #   set to the parent. Rather, it is a toxic caCORE reference which must be purged.
      #   This leaves an empty reference which must be lazy-loaded, which is inefficient and
      #   inconsistent. This situation is rectified in this detoxify method by setting the
      #   dependent owner attribute to the fetched owner in the detoxification
      #   {Jinx::ReferenceVisitor} copy-match-merge.
      #
      # @param [Resource, <Resource>] toxic the fetched object or objects to detoxify
      # @return [Resource, <Resource>] the detoxified result
      def detoxify(toxic)
        return if toxic.nil?
        # if ProxyWrapper.proxy?(toxic) then
        #   recover_target(toxic)
        # end
        if toxic.collection? then
          toxic.each { |ref| detoxify(ref) }
        else
          @ftchd_vstr.visit(toxic) { |ref| detoxify_object(ref, @ftchd_vstr.from) unless cached?(ref) }
        end
        toxic
      end
      
      private

      # Detoxifies the given domain object. This method is called by {#detoxify} to detoxify a visited
      # object fetched from the database. This method does not detoxify referenced objects.
      # 
      # @param [Resource] toxic the fetched object
      def detoxify_object(toxic, parent)
        logger.debug { "Detoxifying the toxic caCORE result #{toxic.qp}..." }
        Jinx::Introspector.ensure_introspected(toxic.class)
        reconcile_fetched_attributes(toxic, parent)
        clear_toxic_attributes(toxic, parent)
        logger.debug { "Detoxified the toxic caCORE result #{toxic.qp}." }
      end
      
      # Replaces fetched references with cached references where possible.
      # 
      # @param (see #detoxify)
      def reconcile_fetched_attributes(toxic, parent)
        toxic.class.fetched_domain_attributes.each_pair do |fa, fp|
          # the fetched reference
          ref = toxic.send(fa) || next
          # the inverse attribute
          fi = fp.inverse
          # Replace each fetched reference with the cached equivalent, if it exists.
          if fp.collection? then
            ref.to_compact_hash { |mbr| @cache[mbr] if mbr != parent }.each do |fmbr, cmbr|
              if fmbr != cmbr and (fi.nil? or cmbr.send(fi).nil?) then
                ref.delete(fmbr)
                ref << cmbr
                logger.debug { "Replaced fetched #{toxic} #{fa} #{fmbr} with cached #{cmbr}." }
              end
            end
          elsif ref != parent then
            cref = @cache[ref]
            if cref and cref != ref and (fi.nil? or cref.send(fi).nil?) then
              toxic.set_property_value(fa, cref)
              logger.debug { "Replaced fetched #{toxic} #{fa} #{ref} with cached #{cref}." }
            end
          end
        end
      end
      
      # Sets each of the toxic attributes in the given domain object to a non-toxic value
      # as follows:
      # * If the toxic attribute references the given parent, then the property value
      #   is retained, since the parent has been detoxified.
      # * Otherwise, the property is set to the correct {Metadata#empty_value} for the
      #   property type.
      # 
      # @param toxic (see #detoxify)
      # @param [Resource] parent the detoxified object which references the toxic object
      def clear_toxic_attributes(toxic, parent)
        pas = toxic.class.toxic_attributes
        return if pas.empty?
        logger.debug { "Clearing the toxic #{toxic.qp} attributes #{pas.to_series}..." }
        pas.each_pair do |pa, prop|
          # Skip non-Java attributes.
          next unless prop.java_property?
          if prop.domain? and not prop.collection? then
            ref = toxic.send(prop.attribute) || next
            # Skip clearing a parent reference, since the parent is detoxified.
            next if ref == parent
          end
          # The replacement value for an uncached toxic reference is the empty or nil
          # value for the property type.
          value ||= toxic.class.empty_value(pa)
          # Clear the attribute. Use the Java writer method rather than the standard
          # attribute writer method. The standard attribute writer enforces inverse integrity,
          # which potentially requires accessing the current toxic value. The Java writer
          # bypasses inverse integrity.
          toxic.send(prop.java_writer, value)
        end
      end
    end
  end
end