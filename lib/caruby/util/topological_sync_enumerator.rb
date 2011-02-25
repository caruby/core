require 'caruby/util/collection'

class TopologicalSyncEnumerator
  include Enumerable

  def initialize(targets, sources, symbol, &matcher)
    @tgts = targets
    @srcs = sources
    @mthd = symbol
    @matcher = matcher || lambda { |tgt, srcs| srcs.first }
  end

  # Calls the given block on each matching target and source.
  # Returns the matching target => source hash.
  def each # :yields: target, source
    # the parent hashes for targets and sources
    pt = @tgts.to_compact_hash { |tgt| tgt.send(@mthd) }
    ps = @srcs.to_compact_hash { |src| src.send(@mthd) }

    # the child hashes
    ct = LazyHash.new { Array.new }
    cs = LazyHash.new { Array.new }

    # collect the chidren and roots
    rt = @tgts.reject { |tgt| p = pt[tgt]; ct[p] << tgt if p }
    rs = @srcs.reject { |src| p = ps[src]; cs[p] << src if p }

    # the match hash
    matches = {}
    # match recursively
    each_match_recursive(rt, rs, ct, cs) do |tgt, src|
      yield(tgt, src)
      matches[tgt] = src
    end

    matches
  end

  private

  def each_match_recursive(targets, sources, ct, cs, &block)
    # copy the sources
    srcs = sources.dup
    # match each target, removing the matched source for the
    # next iteration
    targets.each do |tgt|
      src = @matcher.call(tgt, srcs) || next
      yield(tgt, src)
      srcs.delete(src)
      each_match_recursive(ct[tgt], cs[src], ct, cs, &block)
    end
  end
end