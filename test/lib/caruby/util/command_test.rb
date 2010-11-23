$:.unshift 'lib'

require "test/unit"

require 'caruby/cli/command'
require 'set'

module CaRuby
  class CommandTest < Test::Unit::TestCase
    def test_empty
      verify_execution(Command.new, "test", {})
    end
    
    def test_args_only
      verify_execution(Command.new(:arg), "test arg", :arg => 'arg')
    end
    
    def test_nonmandatory_argument_option
      verify_execution(Command.new(:opt => :none), "test --opt", :opt => true)
    end
    
    def test_mandatory_argument_option
      verify_execution(Command.new(:opt => :mandatory), "test --opt opt", {:opt => 'opt'})
    end
    
    def test_integer_argument_option
      verify_execution(Command.new(:opt => :integer), "test --opt 1", {:opt => 1})
    end
    
    def test_array_argument_option
      verify_execution(Command.new(:opt => :array), "test --opt a,b", {:opt => ['a', 'b']})
    end
    
    def test_complex
      verify_execution(Command.new(:arg1, :opt1 => :none, :opt2 => :optional, :opt3 => :mandatory),
        "test --opt1 --opt3 opt3 arg1 arg2",
        {:opt1 => true, :opt3 => 'opt3', :arg1 => 'arg1'},
        'arg2')
    end
    
    private
    
    def verify_execution(cmd, s, opts, *args)
      ARGV.clear.concat(s.split[1..-1])
      cmd.start do |copts, *cargs|
        opts.each do |opt, expected|
          actual = copts[opt]
          assert_not_nil(actual, "Command option #{opt} not found.")
          assert_equal(expected, actual, "Command option #{opt} parsed incorrectly.")
        end
        assert_equal(cargs, args, "Command arguments differ.")
      end
    end
  end
end