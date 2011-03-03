require 'caruby/util/options'
require 'caruby/util/collection'

module CaRuby
  class Database
    # Proc that matches fetched sources to targets.
    class FetchedMatcher
      # Initializes a new FetchedMatcher.
      def match(srcs, tgts)
        match_fetched(srcs, tgts)
      end
      
      alias :call :match
      
      private

      # Returns a target => source match hash for the given targets and sources using
      # {Resource#match_in_owner_scope}.
      #
      # @param [<Resource>] sources the domain objects to match with targets
      # @param [<Resource>] targets the domain objects to match with targets
      # @return [{Resource => Resource}] the source => target matches
      def match_fetched(sources, targets)
        return Hash::EMPTY_HASH if sources.empty? or targets.empty?
        # the domain class
        klass = sources.first.class
        # the non-owner secondary key domain attributes
        attrs = klass.secondary_key_attributes.select do |attr|
          attr_md = klass.attribute_metadata(attr)
          attr_md.domain? and not attr_md.owner?
        end
        
        # fetch the non-owner secondary key domain attributes as necessary 
        unless attrs.empty? then
          sources.each do |src|
            attrs.each do |attr|
              next if src.send(attr)
              logger.debug { "Fetching #{src.qp} #{attr} in order to match on the secondary key..." }
              ref = src.query(attr).first || next
              src.set_attribute(attr, ref)
              logger.debug { "Set fetched #{src.qp} secondary key attribute #{attr} to fetched #{ref}." }
            end
          end
        end
        
        # match source => target based on the secondary key
        unmatched = Set === sources ? sources.dup : sources.to_set
        matches = {}
        targets.each do |tgt|
          src = tgt.match_in_owner_scope(unmatched)
          next unless src
          matches[src] = tgt
          unmatched.delete(src)
        end
        
        matches
      end
    end
  end
end