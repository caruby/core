caRuby coding style procedure
=============================
This SOP describes how caRuby code is formatted and documented.

Indentation
-----------
Tabs are two spaces. 

Scope
-----
Methods are scoped as conservatively as possible, i.e.:

* a method is `private` if the caller instance is the same as the called instance.

* a method is `protected` if the caller and called instance differ but belong to
  the declaring class.
  
* otherwise, a method is `public`.

`public` definitions occur prior to `protected` definitions which occur prior to
`private` definitions.

Constants
---------
Literals are represented as constants, e.g:

        class Specimen
          class Type
            FROZEN = 'Frozen Specimen'
            ...
          end
        end

Names
-----
Class names are mixed-case without dashes, variable and method names are lower-case with dashes.

Instance variables with an accessor are descriptive, e.g.:

        class Specimen
          attr :specimen_type
          
          def initalize
            @specimen_type = ...
            ...
          end

Local variables are named with short consonants. Variables are described in a comment when
defined if the meaning is not apparent from the context, e.g.:

        def save
          # the execution context
          ctxt = ...
          ...
        end

Conditions
----------
The `then` keyword is included wherever it is accepted, e.g.:

        if spc.specimen_type == Specimen::Type::FROZEN then
          ...
        end

Multi-line conditions use `then`-`else`-`end` rather than braces `{`-`}`.

`and`, `or` and `not` are used in preference to `&&`, `||` and `!`, resp.,
except in assignments, e.g.:

        if spc.nil? or spc.specimen_type == Specimen::Type::FROZEN then ...

        frz_flag = spc.nil? || spc.specimen_type == Specimen::Type::FROZEN

Comments
--------
Every constant and method in any scope is documented with a YARD comment.
Each parameter, exception and yield block is documented.

In-line comments are included wherever the intent of code is not obvious.

Descriptions are sentences with a period, whereas YARD tags are phrases without a period, e.g.:

        # Builds a widget that responds to the given signal.
        #
        # @param [Symbol, nil] the optional signal handled by the widget (default all signals)
        # @return [Widget] the new widget
        # @block [signal] processes the signal
        # @blockparam [Symbol] signal the signal received by the widget
        # @raise [ArgumentError] if the signal is not supported
        def make_widget(signal=nil)
          ...
        end
