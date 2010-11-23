require 'caruby/util/options'
require 'caruby/util/collection'
require 'caruby/util/cache'
require 'caruby/util/pretty_print'
require 'caruby/domain/reference_visitor'
require 'caruby/database/search_template_builder'

module CaRuby
  class Database
    # Proc that matches fetched sources to targets.
    class FetchedMatcher < Proc
      # Initializes a new FetchedMatcher.
      #
      # @param [{Symbol => Object}, Symbol, nil] opts the match options
      # @option [Boolean] opts :relaxed flag indicating whether a {Resource#minimal_match?} is
      #   used in the match on the fetched content
      def initialize(opts=nil)
        super() { |srcs, tgts| match_fetched(srcs, tgts) }
        @relaxed = Options.get(:relaxed, opts)
      end
      
      private

      # Returns a target => source match hash for the given targets and sources.
      def match_fetched(sources, targets)
        return Hash::EMPTY_HASH if sources.empty? or targets.empty?
        logger.debug { "Matching database content #{sources.qp} to #{targets.qp}..." }

        # match source => target based on the key
        unmatched = Set === sources ? sources.dup : sources.to_set
        matches = {}
        targets.each do |tgt|
          src = tgt.match_in_owner_scope(unmatched)
          next unless src
          matches[src] = tgt
          unmatched.delete(src)
        end
        
        # match residual targets, if any, on a relaxed criterion
        if @relaxed and matches.size != targets.size then
          unmtchd_tgts = targets.to_set - matches.keys.delete_if { |tgt| tgt.identifier }
          unmtchd_srcs = sources.to_set - matches.values
          min_mtchs = match_minimal(unmtchd_srcs, unmtchd_tgts)
          matches.merge!(min_mtchs)
        end
        
        logger.debug { "Matched database sources to targets #{matches.qp}." } unless matches.empty?
        matches
      end
      
      #@param [<Resource>] sources the source objects to match
      #@param [<Resource>] targets the potential match target objects
      # @return (see #match_saved)
      def match_minimal(sources, targets)
        matches = {}
        unmatched = Set === sources ? sources.to_set : sources.dup
        targets.each do |tgt|
          src = unmatched.detect { |src| tgt.minimal_match?(src) } || next
          matches[src] = tgt
          unmatched.delete(src)
        end
        matches
      end
    end
  end
end