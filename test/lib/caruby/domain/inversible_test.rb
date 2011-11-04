require File.dirname(__FILE__) + '/../../helper'

require "test/unit"
require 'clinical_trials'

# Make a 1:1 bidirectional Study-Consent inverse.

module ClinicalTrials
  shims Study, Consent

  class Study
    attr_accessor :consent
    add_attribute(:consent, ClinicalTrials::Consent)
  end
  
  class Consent
    attr_accessor :study
    add_attribute(:study, ClinicalTrials::Study)
    set_attribute_inverse(:study, :consent)
  end
end

class InversibleTest < Test::Unit::TestCase
  def test_1_1
    s1 = ClinicalTrials::Study.new
    c = ClinicalTrials::Consent.new
    c.study = s1
    assert_same(c, s1.consent, "1:1 inverse not set")
    s2 = ClinicalTrials::Study.new
    c.study = s2
    assert_same(c, s2.consent, "1:1 inverse not updated")
    assert_nil(s1.consent, "1:1 previous inverse not cleared")
    c.study = nil
    assert_nil(s2.consent, "1:1 previous inverse not cleared")
  end

  def test_1_m
    s1 = ClinicalTrials::Study.new
    ev = ClinicalTrials::StudyEvent.new
    ev.study = s1
    assert_same(ev, s1.events.first, "1:M inverse not set")
    s2 = ClinicalTrials::Study.new
    ev.study = s2
    assert_same(ev, s2.events.first, "1:M inverse not updated")
    assert(s1.events.empty?, "1:M previous inverse not cleared")
    ev.study = nil
    assert(s2.events.empty?, "1:M previous inverse not cleared")
  end
end