require File.dirname(__FILE__) + '/../../helper'
require 'test/unit'
require 'caruby/cli/command'
require 'set'

module CaRuby
  class CommandTest < Test::Unit::TestCase
    def test_empty
      verify_execution(CLI::Command.new, '', {})
    end
    
    def test_arg
      verify_execution(CLI::Command.new([[:arg, 'ARG']]), '4', {:arg => '4'})
    end
    
    def test_option
      verify_execution(CLI::Command.new([[:opt, '--opt N', 'option']]), '--opt 4', {:opt => '4'})
    end
    
    def test_typed_option
      verify_execution(CLI::Command.new([[:opt, '--opt N', Integer, 'option']]), '--opt 4', {:opt => 4})
    end
    
    def test_both
      verify_execution(CLI::Command.new([[:arg, 'ARG'], [:opt, '--opt N', 'option']]), '4 --opt 5', {:arg => '4', :opt => '5'})
    end
   
    private
    
    def verify_execution(cmd, s, expected)
      ARGV.clear.concat(s.split)
      cmd.start do |actual|
        actual.each do |opt, aval|
          eval = expected[opt]
          assert_not_nil(aval, "Command option #{opt} not found.")
          assert_equal(eval, aval, "Command option #{opt} parsed incorrectly.")
        end
      end
    end
  end
end