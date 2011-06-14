$:.unshift 'lib'
$:.unshift 'examples/clinical_trials/lib'

require 'test/unit'

# open the logger
require 'caruby/util/log'
CaRuby::Log.instance.open('test/results/log/clinical_trials.log', :shift_age => 10, :shift_size => 1048576, :debug => true)

require 'clinical_trials'

# CaRuby::Resource test cases.
class DomainTest < Test::Unit::TestCase
  def setup
    super
    @crd = ClinicalTrials::User.new(:login => 'study.coordinator@test.org')
    address = ClinicalTrials::Address.new(:street => '555 Elm St', :city => 'Burlington', :state => 'VT', :zip_code => '55555')
    @sbj = ClinicalTrials::Subject.new(:name => 'Test Subject', :address => address)
    @study = ClinicalTrials::Study.new(:name => 'Test Study', :coordinator => @crd, :enrollment => [@sbj])
    @evt = ClinicalTrials::StudyEvent.new(:study => @study, :calendar_event_point => 1.0)
  end

  def test_alias
    assert(ClinicalTrials::Study.method_defined?(:events), "Study alias not recognized: events")
    assert_equal(@sbj.address.zip_code, @sbj.address.postal_code, 'zip_code not aliased to postal_code')
    assert_equal(:zip_code, @sbj.address.class.standard_attribute(:postal_code), 'postal_code does not map to a standard attribute symbol')
  end

  def test_redefine
    @sbj.address.zip_code = 55555
    assert_equal('55555', @sbj.address.zip_code, "Address zip_code not redefined to support a numeric value")
  end

  def test_merge_attributes
    assert_same(@study.enrollment.first, @sbj, "Merge incorrect")
  end

  def test_owner_inverse_setter
    assert_equal([@evt], @study.events.to_a, 'Event not added to owner events')
    # add another event
    # note: calendar_event_point must be unique within the study or it won't be added to the study events set
    @evt.calendar_event_point = 1.0
    ClinicalTrials::StudyEvent.new(:study => @study, :calendar_event_point => 2.0)
    assert_equal(2, @study.events.to_a.size, 'Second event not added to owner events')
  end

  def test_study_defaults
    assert_nil(@study.activity_status, 'Activity status is already set')
    @study.add_defaults
    assert_equal('Active', @study.activity_status, 'Activity status is not set to default')
  end

  def test_event_defaults
    @evt.calendar_event_point = nil
    @evt.add_defaults
    assert_equal(1.0, @evt.calendar_event_point, 'Event calendar_event_point is not set to default')
  end

  # Tests whether add_defaults method propagates to dependents.
  def test_participant_defaults
    assert_nil(@sbj.address.country, 'Subject address country is already set')
    @sbj.add_defaults
    assert_equal('US', @sbj.address.country, 'Subject address country is not set to default')
  end

  def test_dependents
    assert_equal([@evt], @study.dependents.to_a, "Study dependents incorrect")
    assert(@evt.dependent?, "Event not dependent")
  end

  def test_searchable_attributes
    assert_equal([:name], @study.searchable_attributes.to_a, "Study finder attributes without identifier incorrect")
  end

  def test_event_key
    @evt.calendar_event_point = 1.0
    assert_equal([@study, 1.0], @evt.key, "Event key incorrect")
  end

  def test_address_key
    assert_nil(@sbj.address.key, "Address key incorrect")
  end

  def test_set_collection_attribute
    consent = ClinicalTrials::Consent.new(:statement => 'Test Statement 1')
    consents = @study.consents << consent
    other_consent = ClinicalTrials::Consent.new(:statement => 'Test Statement 2')
    @study.set_attribute(:consents, [other_consent])
    assert_equal([other_consent], @study.consents.to_a, "Consents not set")
    assert_same(consents, @study.consents)
  end

  def test_value_hash
    assert_equal({:study => @study}, @evt.value_hash([:identifier, :study]), "Event value hash incorrect")
  end

  def test_reference_closure
    assert_equal([@study, @evt], @study.reference_hierarchy { |ref| ref.class.dependent_attributes }.to_a, "Reference closure with block incorrect")
  end

  def test_visit_path
    visited = []
    @study.visit_path([:enrollment, :address]) { |ref| visited << ref }
    assert_equal([@study, @sbj, @sbj.address], visited, "Path visitor incorrect")
  end

  def test_visit_dependents
    visited = []
    @study.visit_dependents { |ref| visited << ref }
    assert_equal([@study, @evt], visited, "Dependents visitor incorrect")
  end
end