require 'enumerator'
require 'generator'
require 'caruby/util/options'
require 'caruby/util/collection'
require 'caruby/util/validation'
require 'caruby/util/visitor'
require 'caruby/util/math'

module CaRuby
  # A ReferenceVisitor traverses reference attributes.
  class ReferenceVisitor < Visitor
    private

    # Flag to print a detailed debugging visit message
    DETAIL_DEBUG = false

    public

    attr_reader :ref_attr_hash

    # Creates a new ReferenceVisitor on domain reference attributes.
    #
    # If a selector block is given to this initializer, then the reference attributes to visit
    # are determined by calling the block. Otherwise, the {Domain::Attributes#saved_domain_attributes}
    # are visited.
    #
    # @param options (see Visitor#initialize)
    # @yield [ref] selects which attributes to visit next
    # @yieldparam [Resource] ref the currently visited domain object
    def initialize(options=nil, &selector)
      raise ArgumentError.new("Reference visitor missing domain reference selector") unless block_given?
      @selector = selector
      # delegate to Visitor with the visit selector block
      super { |parent| references_to_visit(parent) }
      # the visited reference => parent attribute hash
      @ref_attr_hash = {}
      # TODO - reconcile @excludes here with Visitor exclude.
      # refactor usage and interaction with prune_cycles.
      # eliminate if possible.
      @excludes = []
    end

    # @return [Symbol, nil] the parent attribute which was visited to get to the current visited domain object
    def attribute
      @ref_attr_hash[current]
    end

    # Excludes obj from the next visit.
    # Exclusions are cleared after visit is completed.
    def exclude(obj)
      @excludes << obj
    end

    # Performs Visitor::visit and clears exclusions.
    def visit(obj)
      if DETAIL_DEBUG then
        logger.debug { "Visiting #{obj.qp} from navigation path #{lineage.qp}..." }
      end
      
      # TODO - current, attribute and parent are nil when a value is expected.
      # Uncomment below, build test cases, analyze and fix.
      #
      # puts "Visit #{obj.qp} current: #{self.current.qp} parent: #{self.parent.qp} attribute: #{self.attribute}"
      # puts "  lineage:#{lineage.qp}n  attributes:#{@ref_attr_hash.qp}"
      # puts "  reference => attribute hash: #{@ref_attr_hash.qp}"

      result = super
      @excludes.clear
      result
    end

    # Adds a default matcher block if necessary and delegates to {Visitor#sync}. The default matcher block
    # calls {Resource#match_in} to match the candidate domain objects to visit.
    #
    # @yield [ref, others] matches ref in others (optional)
    # @yieldparam [Resource] ref the domain object to match
    # @yieldparam [<Resource>] the candidates for matching ref
    def sync(&matcher)
      MatchVisitor.new(:matcher => matcher, &@selector)
    end

    protected

    def clear
      super
      @ref_attr_hash.clear
    end

    private
    
    # @param [Resource] parent the referencing domain object
    # @return [<Resource>] the domain attributes to visit next
    def attributes_to_visit(parent)
       @selector.call(parent)
    end

    # @param [Resource] parent the referencing domain object
    # @return [<Resource>] the referenced domain objects to visit next for the given parent
    def references_to_visit(parent)
      attrs = attributes_to_visit(parent)
      if attrs.nil? then return Array::EMPTY_ARRAY end
      refs = []
      attrs.each do | attr|
        # the reference(s) to visit
        value = parent.send(attr)
        # associate each reference to visit with the current visited attribute
        value.enumerate do |ref|
          @ref_attr_hash[ref] = attr
          refs << ref
        end
      end
      if DETAIL_DEBUG then
        logger.debug { "Visiting #{parent.qp} references: #{refs.qp}" }
        logger.debug { " lineage: #{lineage.qp}" }
        logger.debug { " attributes: #{attrs.qp}..." }
      end
      
      refs
    end
  end
  
  # A MatchVisitor visits two domain objects' visitable attributes transitive closure in lock-step.
  class MatchVisitor < ReferenceVisitor

    attr_reader :matches

    # Creates a new visitor which matches source and target domain object references.
    # The domain attributes to visit are determined by calling the selector block given to
    # this initializer. The selector arguments consist of the match source and target.
    #
    # @param (see ReferenceVisitor#initialize)
    # @option opts [Proc] :mergeable the block which determines which attributes are merged
    # @option opts [Proc] :matchable the block which determines which attributes to match
    #   (default is the visit selector)
    # @option opts [Proc] :matcher the block which matches sources to targets
    # @option opts [Proc] :copier the block which copies an unmatched source
    # @yield (see ReferenceVisitor#initialize)
    # @yieldparam [Resource] source the matched source object
    def initialize(opts=nil)
      raise ArgumentError.new("Reference visitor missing domain reference selector") unless block_given?
      opts = Options.to_hash(opts)
      @matcher = opts.delete(:matcher) || Resource.method(:match_all)
      @matchable = opts.delete(:matchable)
      @copier = opts.delete(:copier)
      # the source => target matches
      @matches = {}
      # the class => {id => target} hash
      @id_mtchs = LazyHash.new { Hash.new }
      super { |src| yield(src) if @matches[src] }
    end

    # Visits the source and target.
    #
    # If a block is given to this method, then this method returns the evaluation of the block on the visited
    # source reference and its matching copy, if any. The default return value is the target which matches
    # source.
    #
    # caCORE alert = caCORE does not enforce reference identity integrity, i.e. a search on object _a_
    # with database record references _a_ => _b_ => _a_, the search result might be _a_ => _b_ => _a'_,
    # where _a.identifier_ == _a'.identifier_. This visit method remedies this caCORE defect by matching
    # source references on a previously matched identifier where possible.
    #
    # @param [Resource] source the match visit source
    # @param [Resource] target the match visit target
    # @yield [target, source] the optional block to call on the matched source and target
    # @yieldparam [Resource] source the visited source domain object
    # @yieldparam [Resource] target the domain object which matches the visited source
    def visit(source, target, &block)
      # clear the match hashes
      @matches.clear
      @id_mtchs.clear
      # seed the matches with the top-level source => target
      add_match(source, target)
      # visit the source reference. the visit block merges each source reference into
      # the matching target reference.
      super(source) { |src| visit_matched(src, &block) }
    end

    private
    
    # Visits the given source domain object.
    #
    # @param [Resource] source the match visit source
    # @yield [target, source] the optional block to call on the matched source and target
    # @yieldparam [Resource] source the visited source domain object
    # @yieldparam [Resource] target the domain object which matches the visited source
    def visit_matched(source)
      tgt = match_for_visited(source)
      # match the matchable references, if any
      if @matchable then
        attrs = @matchable.call(source) - attributes_to_visit(source)
        attrs.each { |attr| match_reference(source, tgt, attr) }
      end
      block_given? ? yield(source, tgt) : tgt
    end

    # @param source (see #match_visited)
    # @return [<Resource>] the domain objects referenced by the source to visit next
    def references_to_visit(source)
      # the source match
      target = match_for_visited(source)
      # the attributes to visit
      attrs = attributes_to_visit(source)
      # the matched source references
      match_references(source, target, attrs).keys
    end
    
    # @param source (see #match_visited)
    # @return [<Resource>] the source match
    # @raise [ValidationError] if there is no match
    def match_for_visited(source)
      target = @matches[source]
      if target.nil? then raise ValidationError.new("Match visitor target not found for #{source}") end
      target
    end

    # @param [Resource] source (see #match_visited)
    # @param [Resource] target the source match
    # @param [<Symbol>] attributes the attributes to match on
    # @return [{Resource => Resource}] the referenced attribute matches
    def match_references(source, target, attributes)
      # collect the references to visit
      matches = {}
      attributes.each do |attr|
        matches.merge!(match_reference(source, target, attr))
      end
      matches
    end
    
    # Matches the given source and target attribute references.
    # The match is performed by this visitor's matcher Proc.
    #
    # @param source (see #visit)
    # @param target (see #visit)
    # @return [{Resource => Resource}] the referenced source => target matches
    def match_reference(source, target, attribute)
      srcs = source.send(attribute).to_enum
      tgts = target.send(attribute).to_enum
      
      # the match targets
      mtchd_tgts = Set.new
      # capture the matched targets and the the unmatched sources
      unmtchd_srcs = srcs.reject do |src|
        # the prior match, if any
        tgt = match_for(src)
        mtchd_tgts << tgt if tgt
      end
      
      # the unmatched targets
      unmtchd_tgts = tgts.difference(mtchd_tgts)
      # match the residual targets and sources
      rsd_mtchs = @matcher.call(unmtchd_srcs, unmtchd_tgts)
      # add residual matches
      rsd_mtchs.each { |src, tgt| add_match(src, tgt) }
      
      # The source => target match hash.
      # If there is a copier, then copy each unmatched source.
      matches = srcs.to_compact_hash { |src| match_for(src) or copy_unmatched(src) }
      logger.debug { "Match visitor matched #{matches.qp}." } unless matches.empty?
      
      matches
    end

    # @return the target matching the given source
    def match_for(source)
      @matches[source] or identifier_match(source)
    end
    
    def add_match(source, target)
      @matches[source] = target
      @id_mtchs[source.class][source.identifier] = target if source.identifier
      target
    end

    # @return the target matching the given source on the identifier, if any
    def identifier_match(source)
      tgt = @id_mtchs[source.class][source.identifier] if source.identifier
      @matches[source] = tgt if tgt
    end

    # @return [Resource, nil] a copy of the given source if this ReferenceVisitor has a copier,
    #   nil otherwise
    def copy_unmatched(source)
      return unless @copier
      copy = @copier.call(source)
      add_match(source, copy)
    end
  end

  # A MergeVisitor merges a domain object's visitable attributes transitive closure into a target.
  class MergeVisitor < MatchVisitor
    # Creates a new MergeVisitor on domain attributes.
    # The domain attributes to visit are determined by calling the selector block given to
    # this initializer as described in {ReferenceVisitor#initialize}.
    #
    # @param (see MatchVisitor#initialize)
    # @option opts [Proc] :mergeable the block which determines which attributes are merged
    # @option opts [Proc] :matcher the block which matches sources to targets
    # @option opts [Proc] :copier the block which copies an unmatched source
    # @yield (see MatchVisitor#initialize)
    # @yieldparam (see MatchVisitor#initialize)
    def initialize(opts=nil, &selector)
      opts = Options.to_hash(opts)
      # Merge is depth-first, since the source references must be matched, and created if necessary,
      # before they can be merged into the target.
      opts[:depth_first] = true
      @mergeable = opts.delete(:mergeable) || selector
      # each mergeable attribute is matchable
      unless @mergeable == selector then
        opts[:matchable] = @mergeable
      end
      super
    end

    # Visits the source and target and returns a recursive copy of obj and each of its visitable references.
    #
    # If a block is given to this method, then this method returns the evaluation of the block on the visited
    # source reference and its matching copy, if any. The default return value is the target which matches
    # source.
    #
    # caCORE alert = caCORE does not enforce reference identity integrity, i.e. a search on object _a_
    # with database record references _a_ => _b_ => _a_, the search result might be _a_ => _b_ => _a'_,
    # where _a.identifier_ == _a'.identifier_. This visit method remedies the caCORE defect by matching source
    # references on a previously matched identifier where possible.
    #
    # @param [Resource] source the domain object to merge from
    # @param [Resource] target the domain object to merge into 
    # @yield [target, source] the optional block to call on the visited source domain object and its matching target
    # @yieldparam [Resource] target the domain object which matches the visited source
    # @yieldparam [Resource] source the visited source domain object
    def visit(source, target)
      # visit the source reference. the visit block merges each source reference into
      # the matching target reference.
      super(source, target) do |src, tgt|
         merge(src, tgt)
         block_given? ? yield(src, tgt) : tgt
      end
    end

    private

    # Merges the given source object into the target object.
    #
    # @param [Resource] source the domain object to merge from
    # @param [Resource] target the domain object to merge into
    # @return [Resource] the merged target
    def merge(source, target)
      # trivial case
      return target if source.equal?(target)
      # the domain attributes to merge
      attrs = @mergeable.call(source)
      logger.debug { format_merge_log_message(source, target, attrs) }
      # merge the non-domain attributes
      target.merge_attributes(source)
      # merge the source domain attributes into the target
      target.merge(source, attrs, @matches)
    end
    
    # @param source (see #merge)
    # @param target (see #merge)
    # @param attributes (see Mergeable#merge)
    # @return [String] the log message
    def format_merge_log_message(source, target, attributes)
      attr_clause = " including domain attributes #{attributes.to_series}" unless attributes.empty?
      "Merging #{source.qp} into #{target.qp}#{attr_clause}..."
    end
  end

  # A CopyVisitor copies a domain object's visitable attributes transitive closure.
  class CopyVisitor < MergeVisitor
    # Creates a new CopyVisitor with the options described in {MergeVisitor#initialize}.
    # The default :copier option is {Resource#copy}.
    #
    # @param (see MergeVisitor#initialize)
    # @option opts [Proc] :mergeable the mergeable domain attribute selector
    # @option opts [Proc] :matcher the match block
    # @option opts [Proc] :copier the unmatched source copy block
    # @yield (see MergeVisitor#initialize)
    # @yieldparam (see MergeVisitor#initialize)
    def initialize(opts=nil)
      opts = Options.to_hash(opts)
      opts[:copier] ||= Proc.new { |src| src.copy }
      # no match forces a copy
      opts[:matcher] = Proc.new { Hash::EMPTY_HASH }
      super
    end

    # Visits obj and returns a recursive copy of obj and each of its visitable references.
    #
    # If a block is given to this method, then the block is called with the visited
    # source reference and its matching copy target.
    #
    # @param (see MergeVisitor#visit)
    # @yield (see MergeVisitor#visit)
    # @yieldparam (see MergeVisitor#visit)
    def visit(source)
      target = @copier.call(source)
      super(source, target)
    end
  end

  # A ReferencePathVisitorFactory creates a ReferenceVisitor that traverses an attributes path.
  #
  # For example, given the attributes:
  #   treatment: BioMaterial -> Treatment
  #   measurement: Treatment -> BioMaterial
  # then a path visitor given by:
  #   ReferencePathVisitorFactory.create(BioMaterial, [:treatment, :measurement])
  # visits all biomaterial, treatments and measurements derived directly or indirectly from a starting BioMaterial instance.
  class ReferencePathVisitorFactory
    # @return a new ReferenceVisitor that visits the given path attributes starting at an instance of type
    def self.create(type, attributes, options=nil)
      # augment the attributes path as a [class, attribute] path
      path = []
      attributes.each do |attr|
        path << [type, attr]
        type = type.domain_type(attr)
      end

      # make the visitor
      visitor = ReferenceVisitor.new(options) do |ref|
        # collect the path reference attributes whose source match the ref type up to the next position in the path
        max = visitor.lineage.size.min(path.size)
        (0...max).map { |i| path[i].last if ref.class == path[i].first }.compact
      end
    end
  end
end