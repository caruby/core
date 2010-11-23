$:.unshift 'lib'
$:.unshift 'examples/clinical_trials/lib'

require 'set'
require "test/unit"
require 'caruby/csv/csv_mapper'

require 'caruby/util/log' and
CaRuby::Log.instance.open('test/results/log/csv.log', :shift_age => 10, :shift_size => 1048576, :debug => true)

require 'clinical_trials'

class CsvMapperTest < Test::Unit::TestCase
  FIXTURES = File.join('test', 'fixtures', 'caruby', 'csv')

  CONFIG_DIR = File.join(FIXTURES, 'config')

  DATA_DIR = File.join(FIXTURES, 'data')

  def test_read_mapper
    config = File.join(CONFIG_DIR, 'study_fields.yaml')
    csv = File.join(DATA_DIR, 'study.csv')
    mapper = CaRuby::CsvMapper.new(config, ClinicalTrials::StudyEvent, csv)
    assert_equal([ClinicalTrials::StudyEvent], mapper.classes, "Classes incorrect")
    map = {[:calendar_event_point]=>:event_point, [:identifier]=>:id, [:study, :activity_status]=>:status, [:study, :name]=>:study}
    paths = map.keys.to_set
    path_md_sym_hash = mapper.paths(ClinicalTrials::StudyEvent).to_compact_hash { |path| path.map { |attr_md| attr_md.to_sym } }
    assert_equal(paths, path_md_sym_hash.values.to_set, "Paths incorrect")
    path_md_hdr_hash = mapper.paths.to_compact_hash { |path| mapper.header(path) }
    actual = path_md_sym_hash.invert.join(path_md_hdr_hash).to_hash
    assert_equal(map, actual, "Header map incorrect")
  end

  def test_write_mapper
    config = File.join(CONFIG_DIR, 'study_fields.yaml')
    csv = File.join(DATA_DIR, 'dummy.csv')
    headers = ['Id', 'Study', 'Status', 'Event Point']
    mapper = CaRuby::CsvMapper.new(config, ClinicalTrials::StudyEvent, csv, :mode => 'w', :headers => headers)
  end
end