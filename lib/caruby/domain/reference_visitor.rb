require 'enumerator'
require 'generator'
require 'caruby/util/options'
require 'caruby/util/collection'
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
    # are determined by calling the block. Otherwise, the {ResourceAttributes#saved_domain_attributes}
    # are visited.
    #
    # @param options (see Visitor#initialize)
    # @yield [ref] selects which attributes to visit next
    # @yieldparam [Resource] ref the currently visited domain object
    def initialize(options=nil, &selector)
      # use the default attributes if no block given
      @slctr = selector || Proc.new { |obj| obj.class.saved_domain_attributes }
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
    # calls {CaRuby::Resource#match_in} to match the candidate domain objects to visit.
    #
    # @yield [ref, others] matches ref in others (optional)
    # @yieldparam [Resource] ref the domain object to match
    # @yieldparam [<Resource>] the candidates for matching ref
    def sync
      block_given? ? super : super { |ref, others| ref.match_in(others) }
    end

    protected

    def clear
      super
      @ref_attr_hash.clear
    end

    private

    # @return the domain objects to visit next for the given parent
    def references_to_visit(parent)
      attributes = @slctr.call(parent)
      if attributes.nil? then return Array::EMPTY_ARRAY end
      refs = []
      attributes.each do | attr|
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
        logger.debug { " attributes: #{@ref_attr_hash.qp}..." }
      end
      refs
    end
  end

  # A MergeVisitor merges a domain object's visitable attributes transitive closure into a target.
  class MergeVisitor < ReferenceVisitor

    attr_reader :matches

    # Creates a new MergeVisitor on domain attributes.
    # The domain attributes to visit are determined by calling the selector block given to
    # this initializer as described in {ReferenceVisitor#initialize}.
    #
    # @param [Hash] options the visit options
    # @option options [Proc] :mergeable the mergeable domain attribute selector
    # @option options [Proc] :matcher the match block
    # @option options [Proc] :copier the unmatched source copy block
    # @yield [source, target] the visit domain attribute selector block
    # @yieldparam [Resource] source the current merge source domain object
    # @yieldparam [Resource] target the current merge target domain object
    def initialize(options=nil, &selector)
      raise ArgumentError.new("Reference visitor missing domain reference selector") unless block_given?
      options = Options.to_hash(options)
      @mergeable = options.delete(:mergeable) || selector
      @matcher = options.delete(:matcher) || Resource.method(:match_all)
      @copier = options.delete(:copier)
      # the source => target matches
      @matches = {}
      # the class => {id => target} hash
      @id_mtchs = LazyHash.new { Hash.new }
      super do |src|
        tgt = @matches[src]
        yield(src, tgt) if tgt
      end
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
    # @param [Resource] target the domain object to merge into 
    # @param [Resource] source the domain object to merge from
    # @yield [target, source] the optional block to call on the visited source domain object and its matching target
    # @yieldparam [Resource] target the domain object which matches the visited source
    # @yieldparam [Resource] source the visited source domain object
    def visit(target, source)
      # clear the match hashes
      @matches.clear
      @id_mtchs.clear
      # seed the matches with the top-level source => target
      add_match(source, target)
      # visit the source reference. the visit block merges each source reference into
      # the matching target reference.
      super(source) do |src|
        tgt = match(src) || next
        merge(tgt, src)
        block_given? ? yield(tgt, src) : tgt
      end
    end

    private

    # Merges the given source object into the target object.
    #
    # @param [Resource] target thedomain object to merge into
    # @param [Resource] source the domain object to merge from
    def merge(target, source)
      # the domain attributes to merge; non-domain attributes are always merged
      attrs = @mergeable.call(source, target)
      # Match each source reference to a target reference.
      target.merge_match(source, attrs, &method(:match_all))
      target
    end

    # Matches the given sources to targets. The match is performed by this visitor's matcher Proc.
    #
    # @param [<Resource>] sources the domain objects to match
    # @param [<Resource>] targets the match candidates
    # @return [{Resource => Resource}] the source => target matches
    def match_all(sources, targets)
     # the match targets
      mtchd_tgts = Set.new
      # capture the matched targets and the the unmatched sources
      unmtchd_srcs = sources.reject do |src|
        # the prior match, if any
        tgt = match(src)
        mtchd_tgts << tgt if tgt
      end
      # the unmatched targets
      unmtchd_tgts = targets.difference(mtchd_tgts)

      # match the residual targets and sources
      rsd_mtchs = @matcher.call(unmtchd_srcs, unmtchd_tgts)
      # add residual matches
      rsd_mtchs.each { |src, tgt| add_match(src, tgt) }
      # The source => target match hash.
      # If there is a copier, then copy each unmatched source.
      matches = sources.to_compact_hash { |src| match(src) or copy_unmatched(src) }
      logger.debug { "Merge visitor matched #{matches.qp}." } unless matches.empty?
      matches
    end

    # @return the target matching the given source
    def match(source)
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

    # @return [Resource, nil] a copy of the given source if this ReferenceVisitor has a copier, nil otherwise
    def copy_unmatched(source)
      return unless @copier
      copy = @copier.call(source)
      add_match(source, copy)
    end
  end

  # A CopyVisitor copies a domain object's visitable attributes transitive closure.
  class CopyVisitor < MergeVisitor
    # Creates a new CopyVisitor with the options described in {MergeVisitor#initialize}.
    # The default :copier option is {Resource#copy}.
    def initialize(options=nil) # :yields: source
      options = Options.to_hash(options)
      options[:copier] ||= Proc.new { |src| src.copy }
      super
    end

    # Visits obj and returns a recursive copy of obj and each of its visitable references.
    #
    # If a block is given to this method, then the block is called with the visited
    # source reference and its matching copy target.
    def visit(source, &block) # :yields: target, source
      target = @copier.call(source)
      super(target, source, &block)
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