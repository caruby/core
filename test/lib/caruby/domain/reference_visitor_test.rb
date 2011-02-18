$:.unshift 'lib'
$:.unshift 'examples/clinical_trials/lib'

require 'test/unit'

require 'caruby/util/log' and
CaRuby::Log.instance.open('test/results/log/clinical_trials.log', :shift_age => 10, :shift_size => 1048576, :debug => true)

require 'clinical_trials'
require 'caruby/domain/reference_visitor'

# CaRuby::ReferenceVisitor test cases.
class ReferenceVisitorTest < Test::Unit::TestCase
  def setup
    super
    coordinator = ClinicalTrials::User.new(:login => 'study.coordinator@test.org')
    address = ClinicalTrials::Address.new(:street => '555 Elm St', :city => 'Burlington', :state => 'VT', :zip_code => '55555')
    @pnt = ClinicalTrials::Participant.new(:name => 'Test Participant', :address => address)
    @study = ClinicalTrials::Study.new(:name => 'Test Study', :coordinator => coordinator, :enrollment => [@pnt])
    @event = ClinicalTrials::StudyEvent.new(:study => @study, :calendar_event_point => 1.0)
  end

  def test_path_references
    visitor = CaRuby::ReferencePathVisitorFactory.create(ClinicalTrials::Study, [:enrollment, :address])
    assert_equal([@study, @pnt, @pnt.address], visitor.to_enum(@study).to_a, "Path references incorrect")
  end

  def test_cycles
    # visit all references
    visitor = CaRuby::ReferenceVisitor.new { |ref| ref.class.domain_attributes }
    visitor.visit(@study)
    assert_equal([[@study, @event, @study]], visitor.cycles, "Cycles incorrect")
  end

  def test_path_attributes
    visitor = CaRuby::ReferencePathVisitorFactory.create(ClinicalTrials::Study, [:enrollment, :address])
    assert_equal([nil, :enrollment, :address], visitor.to_enum(@study).map { visitor.attribute }, "Path attributes incorrect")
  end

  def test_to_enum
    visitor = CaRuby::ReferencePathVisitorFactory.create(ClinicalTrials::Study, [:enrollment, :address])
    assert_equal([@study, @pnt, @pnt.address], visitor.to_enum(@study).to_a, "Enumeration incorrect")
  end

  def test_id_match
    # set the source ids
    @study.identifier = 1
    @event.identifier = 2
    # make a match target
    target = CaRuby::CopyVisitor.new { |ref| ref.class.dependent_attributes }.visit(@study)
    # match the source to the target
    matcher = CaRuby::MatchVisitor.new { |ref| ref.class.dependent_attributes }
    matcher.visit(@study, target)
    expected = {@study => target, @event => target.events.first}
    # validate the match
    assert_equal(expected, matcher.matches, "Match incorrect")
  end

  def test_copy
    visitor = CaRuby::CopyVisitor.new { |ref| ref.class.dependent_attributes }
    copy = visitor.visit(@study)
    assert_not_nil(copy, "Study not copied")
    assert_not_nil(visitor.visited[@study], "#{@study.qp} copy #{copy.qp} not captured in visited #{visitor.visited.qp}")
    assert_same(copy, visitor.visited[@study], "#{@study.qp} visited value incorrect")
    assert_not_same(copy, @study, "#{@study.qp} not copied into #{copy.qp} as new object")
    assert_equal(@study.name, copy.name, "#{@study.qp} attribute not copied")
    assert_nil(copy.coordinator, "#{@study.qp} coordinator incorrectly copied into #{copy.qp} as a dependent")
    assert(!@study.events.empty?, "#{@study.qp} events cleared by copy")
    assert(!copy.events.empty?, "#{@study.qp} events #{@study.events.qp} not copied into #{copy.qp}")
    assert_equal(1, copy.events.size, "#{@study.qp} events copy #{copy.qp} size incorrect")
    assert_not_same(copy.events.first, @study.events.first, "#{@study.qp} event #{@study.events.first} not copied into #{copy.qp} as new object")
    assert_same(copy, copy.events.first.study, "Dependent owner attribute not set to copied owner #{copy.qp}")
  end

  def test_merge
    # make a merge target
    target = CaRuby::CopyVisitor.new { |ref| ref.class.dependent_attributes }.visit(@study)
    # set the source ids
    @study.identifier = 1
    @event.identifier = 2
    
    # merge into the copy
    merger = CaRuby::MergeVisitor.new { |ref| ref.class.dependent_attributes }
    merger.visit(@study, target)
    
    # validate that the ids are copied
    assert_equal(@study.identifier, target.identifier, "Merge didn't copy the study identifier")
    assert_not_nil(target.events.first, "Merge didn't copy #{@study.qp} event #{@event.qp} to #{target.qp}")
    assert_equal(target.events.first.identifier, @event.identifier, "Merge didn't copy #{@study.qp} event #{@event.qp} event identifier to  #{target.qp}")
  end

  def test_copy_id_match
    # set the study id
    @study.identifier = 1
    # mutate the references a la caCORE to form reference path @study -> @event -> s2,
    # where @study.identifier == s2.identifier
    s2 = @study.copy(:identifier)
    @event.study = s2
    s2.events.clear
    @study.events << @event
    
    # copy the mutated source
    copier = CaRuby::CopyVisitor.new { |ref| ref.class.dependent_attributes }
    copy = copier.visit(@study)
    
    # validate the copy
    assert_not_nil(copy.events.first, "Merge didn't copy event")
    assert_same(copy, copy.events.first.study, "Merge didn't match on study id")
  end

  def test_copy_with_visit_block
    visitor = CaRuby::CopyVisitor.new { |ref| ref.class.domain_attributes }
    id = visitor.visit(@study) { |src, tgt| src.identifier }
    assert_equal(@study.identifier, id, "Visit didn't return block result")
  end

  def test_copy_revisit_same_object
    # make a new event in the study, resulting in two paths to the study
    ClinicalTrials::StudyEvent.new(:study => @study, :calendar_event_point => 2.0)
    # eliminate extraneous references
    @study.coordinator = nil
    @study.enrollment.clear
    # visit all references, starting at an event, with traversal event -> study -> other event -> study
    visitor = CaRuby::CopyVisitor.new { |ref| ref.class.domain_attributes }
    visited = visitor.visit(@event)
    studies = visitor.visited.select { |ref, copy| ClinicalTrials::Study === ref }
    assert(!studies.empty?, "No study copied")
    assert_equal(1, studies.size, "More than one study copied")
  end
end