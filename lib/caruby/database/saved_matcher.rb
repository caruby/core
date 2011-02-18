require 'caruby/database/fetched_matcher'

module CaRuby
  class Database
    # Proc that matches saved result sources to targets.
    class SavedMatcher < FetchedMatcher
      # Initializes a new SavedMatcher.
      def initialize
        super
      end
      
      private

      # Returns a target => source match hash for the given targets and sources.
      #
      # @param (see FetchedMatcher#initialize)
      # @return (see FetchedMatcher#initialize)
      def match_fetched(sources, targets)
        # match source => target based on the key
        matches = super
        # match residual targets, if any, on a relaxed criterion
        if matches.size != targets.size and not sources.empty? then
          match_fetched_residual(sources, targets, matches)
        end
        matches
      end

      # Adds to the given target => source matches hash for the unmatched targets and sources
      # using {#match_minimal}.
      #
      # @param sources (see #match_fetched)
      # @param targets (see #match_fetched)
      # @param [{Resource => Resource}] the source => target matches so far
      def match_fetched_residual(sources, targets, matches)
        unmtchd_tgts = targets.to_set - matches.keys.delete_if { |tgt| tgt.identifier }
        unmtchd_srcs = sources.to_set - matches.values
        min_mtchs = match_minimal(unmtchd_srcs, unmtchd_tgts)
        matches.merge!(min_mtchs)
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