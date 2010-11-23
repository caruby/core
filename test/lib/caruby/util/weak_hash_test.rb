$:.unshift 'lib'
$:.unshift 'examples/clinical_trials/lib'

require 'caruby/util/log'
CaRuby::Log.instance.open('test/results/log/clinical_trials.log', :shift_age => 10, :shift_size => 1048576, :debug => true)

require 'caruby/util/weak_hash'
require 'clinical_trials'
require File.join(File.dirname(__FILE__), '..', 'test_case')

class WeakHashTest < Test::Unit::TestCase
   def setup
    @hash = CaRuby::WeakHash.new
  end

  def test_accessors
    study = ClinicalTrials::Study.new(:identifier => 1)
    @hash[1] = study
    assert_equal(study, @hash[1], "Value not found for key")
  end

  def test_each
    study = ClinicalTrials::Study.new(:identifier => 1)
    @hash[1] = study
    assert_equal([[1, study]], @hash.to_a, "Weak hash enumeration incorrect")
  end

  # Verify that a strongly referenced hash entry is not reclaimed and weakly referenced entries are
  # eventually reclaimend.
  def test_stress
    # a strongly referenced entry
    pinned = @hash[1] = ClinicalTrials::Study.new(:identifier => 1)
    # make weakly referenced entries until one is reclaimed
    2.upto(1000000) do |n|
      @hash[n] = ClinicalTrials::Study.new(:identifier => n)
      # the strongly referenced entry should always be retained.
      # note that the test fails if the reference is @hash[1]. jRuby or Java probably
      # optimize @hash[1] into a strong reference, but not @hash[pinned.identifier].
      assert_not_nil(@hash[pinned.identifier], "Strongly referenced hash entry reclaimed")
      # done when the second entry is reclaimed
      return unless @hash[2]
    end
    fail("Weak hash entries not garbage-collected after 1,000,000 entries")
  end
end