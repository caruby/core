require File.dirname(__FILE__) + '/../../helper'

require 'test/unit'
require 'ftools'
require 'date'
require 'caruby/csv/csvio'
require 'caruby/helpers/file_separator'

class CaRuby::CsvIOTest < Test::Unit::TestCase
  TEST_DIR = File.dirname(__FILE__) + '/../../..'
  FIXTURES_DIR = TEST_DIR + '/fixtures/caruby/csv/data'
  OUTPUT_DIR = TEST_DIR + '/results/caruby/csv'

  def setup
    File.makedirs(OUTPUT_DIR)
  end

  def test_read
    loader = CaRuby::CsvIO.new(File.join(FIXTURES_DIR, 'variety.csv'))
    loader.each do |row|
      assert_not_nil(row[:id], "Missing id")
      assert_not_nil(row[:string_field], "Missing string_field")
      assert_not_nil(row[:integer], "Missing integer method")
      assert(Integer === row[:integer], "Incorrect integer field value type")
      assert_not_nil(row[:float], "Missing float method")
      assert(Float === row[:float], "Incorrect float field value type")
      assert_not_nil(row[:date], "Missing date method")
      assert_equal(Date, row[:date].class, "Incorrect date field value type")
    end
  end

  def test_empty
    loader = CaRuby::CsvIO.new(File.join(FIXTURES_DIR, 'empty.csv'))
    row = loader.shift
    assert_nil(row[:one], "Missing value not nil")
    assert_nil(row[:two], "Missing value not nil")
  end

  def test_accessor
    loader = CaRuby::CsvIO.new(File.join(FIXTURES_DIR, 'variety.csv'))
    assert_equal(:id, loader.accessor('Id'), "Accessor incorrect")
    assert_equal(:string_field, loader.accessor('String Field'), "Accessor incorrect")
  end

  def test_write
    input = File.join(FIXTURES_DIR, 'variety.csv')
    output = File.join(OUTPUT_DIR, 'variety.csv')
    headers = records = nil
    # Read the input file content.
    File.open(input) do |file|
      headers = file.readline.chomp.split(/,\s*/)
      records = file.map { |line| line.chomp.split(/,\s*/) }
    end
    # Write the output file.
    CaRuby::CsvIO.open(output, :mode => 'w', :headers => headers) do |csvio|
      records.each { |rec| csvio << rec }
    end
    # Compare the output to the input.
    File.open(output) do |file|
      assert_equal(headers, file.readline.chomp.split(/,\s*/), "Headers don't match")
      file.each_with_index do |line, i|
        rec = line.chomp.split(/,\s*/)
        assert_equal(records[i], rec, "Line #{i.succ} doesn't match")
      end
    end
  end
end