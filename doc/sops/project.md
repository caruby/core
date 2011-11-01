caRuby project structure
========================
This SOP describes how caRuby git projects are organized.

Git
---
Each caRuby project is named `caruby-` followed by a lower-case, dash-separated qualifier,
e.g. `caruby-tissue-web-service`.

The project repository is created in the GitHub caRuby organization at [github.com/caruby].

Files
-----
Every project includes the following files:

* `README.md` - The Git project landing page text (see below).

* `.gitignore` - standard Git files to ignore, including `doc/api` and derived files

* `History.md` - the gem release history (see below)

* `LEGAL` - legal notice (see below)

* `LICENSE` - the license text (see below)

Directories
-----------
The project directories include the following:

* `bin` - Executable scripts

* `conf` - Configuration files

* `doc` - Non-API documentation

* `examples` - Usage examples

* `lib` - Ruby code

* `views` - [HAML](haml-lang.com) web pages

* `public` - Static web files

* `features` - [Cucumber](cukes.info) definitions 

* `specs` - [Rspec](rspec.info) scenarios 

* `test` - Unit test cases and fixtures

Content
-------
Every file included in the git repository is directly or indirectly required by one of the following:

* An executable or class documented in the README Usage section

* An example

* A test scenario

* Non-API text documentation

No other files are included in git. API RubyDoc is not included.

Documentation
-------------
Formatted rich text documents are written in [Markdown](http://daringfireball.net/projects/markdown/).

All non-API documents reside in the `doc` directory. Only text documents which describe current usage
are included. Word, PDF and other binary documents are not included in git. Specifications are captured
in Cucumber or RSpec, not Word. Usage is described in Markdown or a FAQ, not Word.

Project FAQs reside in the caRuby [Knowledge Base](caruby.tenderapp.com/kb). Each FAQ is also stored and
revised in the `doc/faqs` subdirectory.

Project web pages reside in the caRuby [web site](caruby.rubyforge.org/). Each web page is also stored and
revised in the `doc/website` subdirectory.

For convenience, every caRuby project FAQ and web page is stored in the `caruby-core` git repository rather
than the individual project git repository.

README
------
The README file includes the following sections:

* Header

* Synopsis

* Features

* Installation

* Usage

* Copyright

History
-------
The history file includes a brief entry of the major theme for each release. The history is not
auto-generated from the git log.

Legal Notice
------------
The `LEGAL` file states which files are covered under which licenses.

License
-------
Every caRuby project is released under the MIT open source license.
