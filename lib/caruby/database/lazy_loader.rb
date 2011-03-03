require 'caruby/database/fetched_matcher'

module CaRuby
  class Database
    # A LazyLoader fetches an association from the database on demand.
    class LazyLoader < Proc
      # Creates a new LazyLoader which calls the loader block on the subject.
      #
      # @yield [subject, attribute] fetches the given subject attribute value from the database
      # @yieldparam [Resource] subject the domain object whose attribute is to be loaded
      # @yieldparam [Symbol] attribute the domain attribute to load
      def initialize(&loader)
        super { |sbj, attr| load(sbj, attr, &loader) }
        # the fetch result matcher
        @matcher = FetchedMatcher.new
        @enabled = true
      end
  
      # Disables this lazy loader. If the loader is already disabled, then this method is a no-op.
      # Otherwise, if a block is given, then the lazy loader is reenabled after the block is executed.
      #
      # @yield the block to call while the loader is disabled
      # @return the result of calling the block if a block is given, nil otherwise
      def disable
        reenable = set_disabled
        return unless block_given?
        begin
          yield
        ensure
          set_enabled if reenable
        end
      end
      
      alias :suspend :disable
      
      # Enables this lazy loader. If the loader is already enabled, then this method is a no-op.
      # Otherwise, if a block is given, then the lazy loader is redisabled after the block is executed.
      #
      # @yield the block to call while the loader is enabled
      # @return the result of calling the block if a block is given, nil otherwise
      def enable
        redisable = set_enabled
        return unless block_given?
        begin
          yield
        ensure
          set_disabled if redisable
        end
      end
      
      alias :resume :enable
      
      # @return [Boolean] whether this loader is enabled
      def enabled?
        @enabled
      end
  
      # @return [Boolean] whether this loader is disabled
      def disabled?
        not @enabled
      end
      
      private
  
      # Disables this loader.
      #
      # @return [Boolean] true if this loader was previously enabled, false otherwise
      def set_disabled
        enabled? and (@enabled = false; true)
      end
  
      # Enables this loader.
      #
      # @return [Boolean] true if this loader was previously disabled, false otherwise
      def set_enabled
        disabled? and (@enabled = true)
      end
  
      # @param [Resource] subject the domain object whose attribute is to be loaded
      # @param [Symbol] the domain attribute to load
      # @yield (see #initialize)
      # @yieldparam (see #initialize)
      # @return the attribute value loaded from the database
      # @raise [RuntimeError] if this loader is disabled
      def load(subject, attribute)
        if disabled? then raise RuntimeError.new("#{subject.qp} lazy load called on disabled loader") end
        logger.debug { "Lazy-loading #{subject.qp} #{attribute}..." }
        # the current value
        oldval = subject.send(attribute)
        # load the fetched value
        fetched = yield(subject, attribute)
        # nothing to merge if nothing fetched
        return oldval if fetched.nil_or_empty?
        # merge the fetched into the attribute
        logger.debug { "Merging #{subject.qp} fetched #{attribute} value #{fetched.qp}#{' into ' + oldval.qp if oldval}..." }
        matches = @matcher.match(fetched.to_enum, oldval.to_enum)
        subject.merge_attribute(attribute, fetched, matches)
      end    
    end
  end
end