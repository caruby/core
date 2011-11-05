require File.dirname(__FILE__) + '/../../helper'
require "test/unit"
require 'caruby/util/person'

class PersonTest < Test::Unit::TestCase
  def test_middle_but_no_first
    assert_raises(ValidationError) { || CaRuby::Person::Name.new('Longfellow', nil, 'Wadsworth').validate }
  end

  def test_empty_middle_and_no_first
    assert_raises(ValidationError) { || CaRuby::Person::Name.new(nil, '').validate }
  end

  def test_substitute_nil_for_empty
    name = CaRuby::Person::Name.new('Longfellow', '')
    assert_nil(name.first)
  end

  def test_full_print
    name = CaRuby::Person::Name.new('Longfellow', 'Henry', 'W.')
    assert_equal('Henry W. Longfellow', name.to_s)
  end

  def test_first_and_last_print
    name = CaRuby::Person::Name.new('Longfellow', 'Henry')
    assert_equal('Henry Longfellow', name.to_s)
  end

  def test_last_print
    name = CaRuby::Person::Name.new('Longfellow', '')
    assert_equal('Longfellow', name.to_s)
  end

  def test_first_print
    name = CaRuby::Person::Name.new('', 'Henry')
    assert_equal('Henry', name.to_s)
  end

  def test_parse_last_first
    name = CaRuby::Person::Name.parse('Longfellow, Henry')
    assert_equal('Henry', name.first)
    assert_equal('Longfellow', name.last)
    assert_nil(name.middle)
  end

  def test_parse_last_first_middle
    name = CaRuby::Person::Name.parse('Longfellow, Henry Wadsworth')
    assert_equal('Henry', name.first)
    assert_equal('Longfellow', name.last)
    assert_equal('Wadsworth', name.middle)
  end

  def test_parse_last_first_middles
    name = CaRuby::Person::Name.parse('Longfellow, Henry Gallifant Wadsworth')
    assert_equal('Henry', name.first)
    assert_equal('Longfellow', name.last)
    assert_equal('Gallifant Wadsworth', name.middle)
  end

  def test_parse_first_last
    name = CaRuby::Person::Name.parse('Henry Longfellow')
    assert_equal('Henry', name.first)
    assert_equal('Longfellow', name.last)
    assert_nil(name.middle)
  end

  def test_parse_first_middle_Last
    name = CaRuby::Person::Name.parse('Henry Wadsworth Longfellow')
    assert_equal('Henry', name.first)
    assert_equal('Longfellow', name.last)
    assert_equal('Wadsworth', name.middle)
  end

  def test_salutation_with_middle
    name = CaRuby::Person::Name.parse('Mr. Henry Wadsworth Longfellow')
    assert_equal('Henry', name.first)
    assert_equal('Longfellow', name.last)
    assert_equal('Wadsworth', name.middle)
    assert_equal('Mr.', name.salutation)
  end

  def test_salutation_without_middle
    name = CaRuby::Person::Name.parse('Mr. Henry Longfellow')
    assert_equal('Henry', name.first)
    assert_equal('Longfellow', name.last)
    assert_equal('Mr.', name.salutation)
  end

  def test_qualifier
    name = CaRuby::Person::Name.parse('Henry Wadsworth Longfellow III')
    assert_equal('Henry', name.first)
    assert_equal('Longfellow', name.last)
    assert_equal('Wadsworth', name.middle)
    assert_equal('III', name.qualifier)
  end

  def test_credentials
    name = CaRuby::Person::Name.parse('Henry Wadsworth Longfellow, MD, Ph.D., CPA, Esq')
    assert_equal('Henry', name.first)
    assert_equal('Longfellow', name.last)
    assert_equal('Wadsworth', name.middle)
    assert_equal('MD, Ph.D., CPA, Esq', name.credentials)
  end

  def test_qualifier_and_credentials
    name = CaRuby::Person::Name.parse('Henry Wadsworth Longfellow III, Ph.D.')
    assert_equal('Henry', name.first)
    assert_equal('Longfellow', name.last)
    assert_equal('Wadsworth', name.middle)
    assert_equal('III', name.qualifier)
    assert_equal('Ph.D.', name.credentials)
  end
end