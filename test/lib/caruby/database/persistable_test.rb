require File.dirname(__FILE__) + '/../../helper'

require 'test/unit'
require 'clinical_trials'

class PersistableTest < Test::Unit::TestCase

  def setup
    address = ClinicalTrials::Address.new(:street => '555 Elm St', :city => 'Burlington', :state => 'VT', :zip_code => '55555')
    @sbj = ClinicalTrials::Subject.new(:name => 'Test Subject')
    @study = ClinicalTrials::Study.new(:name => 'Test Study')
    @evt = ClinicalTrials::StudyEvent.new(:calendar_event_point => 1.0)
    @consent = ClinicalTrials::Consent.new(:statement => 'Test statement')
    @loader = lambda { |obj, attr| load(obj, attr) }
    @@counter = 0
    @study.identifier = @@counter += 1
    @study.add_lazy_loader(@loader)
    @references = {
      @study => {:enrollment => [@sbj], :study_events => [@evt], :consents => [@consent]},
      @sbj => {:address => address}
    }
  end

  def test_nothing
  end
  
  # TODO - no longer testable after loader refactoring. Bring test case into compliance.
  # 
  # def test_dependent_reference
  #   assert_not_nil(@study.events.first, "Dependent events reference not loaded")
  #   assert_not_nil(@study.events.first.identifier, "Dependent events reference loaded but identifier not set")
  # end
  # 
  # def test_unidirectional_dependent
  #   assert_nil(@study.consents.first, "Unidirectional dependent consents reference incorrectly loaded")
  #   # explicitly set the consents loader
  #   @study.remove_lazy_loader
  #   @study.add_lazy_loader(@loader)
  #   # verify the load merge
  #   assert_not_nil(@study.consents.first, "Dependent consents reference not loaded")
  #   assert_not_nil(@study.consents.first.identifier, "Dependent consents reference loaded but identifier not set")
  # end
  # 
  # def test_unidirectional_dependent_merge
  #   # explicitly set the consents loader
  #   @study.remove_lazy_loader
  #   @study.add_lazy_loader(@loader)
  #   # verify the load merge
  #   assert_equal(1, @study.consents.size, "Unambiguous dependent consent not merged")
  #   assert_not_nil(@study.consents.first.identifier, "Dependent consents reference loaded but identifier not set")
  # end
  # 
  # def test_unidirectional_dependent_ambiguous_merge
  #   # add the consent
  #   @study.consents << @consent
  #   # make an ambiguous "persistent" consent
  #   @references[@study][:consents] << @consent.copy
  #   # explicitly set the consents loader
  #   @study.remove_lazy_loader
  #   @study.add_lazy_loader(@loader)
  #   # verify the load merge
  #   assert_equal(3, @study.consents.size, "Ambiguous dependent consent not added")
  #   assert_nil(@consent.identifier, "Consent identifier incorrectly merged from ambiguous dependent consent")
  # end
  # 
  # private
  # 
  # def load(obj, attribute)
  #   value = @references[obj][attribute]
  #   CaRuby.fail(ArgumentError, "Value not found for #{attribute}: #{obj}") if value.nil?
  #   duplicate_with_id(value)
  # end
  # 
  # def duplicate_with_id(obj)
  #   return obj.map { |item| duplicate_with_id(item) } if Enumerable === obj
  #   copy = obj.copy
  #   copy.identifier ||= @@counter += 1
  #   copy
  # end
end