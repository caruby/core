require 'jinx/helpers/options'
require 'jinx/helpers/collection'

module CaRuby
  class Database
    # Helper that matches fetched sources to targets.
    class FetchedMatcher
      # Returns a target => source match hash for the given targets and sources using
      # {Jinx::Resource#match_in_owner_scope}.
      #
      # caCORE alert = caCORE does not enforce reference identity integrity, i.e. a search on object _a_
      # with database record references _a_ => _b_ => _a_, the search result might be _a_ => _b_ => _a'_,
      # where _a.identifier_ == _a'.identifier_. This visit method remedies this caCORE defect by matching
      # source references on a previously matched identifier where possible.
      #
      # @param [<Jinx::Resource>] sources the domain objects to match against
      # @param [<Jinx::Resource>] targets the domain objects to match
      # @param [Resource] from the visiting domain object
      # @param [Symbol] attribute the visiting attribute
      # @return [{Jinx::Resource => Jinx::Resource}] the source => target matches
      def match(sources, targets, from, attribute)
        if sources.empty? or targets.empty? then
          Hash::EMPTY_HASH 
        elsif from.class.property(attribute).owner? then
          match_owner(sources.first, targets.first, from, attribute)
        else
          match_fetched(sources, targets)
        end
      end
      
      private
      
      # @param [<Jinx::Resource>] source the fetched owner to match against
      # @param [<Jinx::Resource>] target the owner to match
      # @param [Resource] dependent the visiting dependent
      # @param attribute (see #match)
      # @return [{Resource => Resource}] the source => target singleton hash, if the source
      #   and target identifiers don't conflict, otherwise an empty hash
      def match_owner(source, target, dependent, attribute)
        return Hash::EMPTY_HASH unless source.minimal_match?(target)
        logger.debug { "Matched #{dependent} #{attribute} owner #{source} to #{target}." }
        {source => target}
      end

      # Fetches the given domain objects non-owner secondary key domain attributes as necessary.
      def fetch_secondary_key_references(sources)
        # fetch the secondary key reference if necessary
        sources.each do |src|
          src.class.secondary_key_non_owner_domain_attributes.each do |pa|
            next if src.send(pa)
            logger.debug { "Fetching #{src.qp} #{pa} in order to match on the secondary key..." }
            ref = src.query(pa).first || next
            src.set_property_value(pa, ref)
            logger.debug { "Set fetched #{src.qp} secondary key attribute #{pa} to fetched #{ref}." }
          end
        end
      end
      
      def match_fetched(sources, targets)
        # complete the key
        fetch_secondary_key_references(sources)
        # match source => target based on the secondary key
        unmatched = Set === sources ? sources.dup : sources.to_set
        matches = {}
        targets.each do |tgt|
          src = tgt.match_in_owner_scope(unmatched) || next
          matches[src] = tgt
          unmatched.delete(src)
        end
        matches
      end
    end
  end
end