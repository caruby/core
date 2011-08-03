Each caRuby [component](faq/components) is packaged as a standard Ruby [gem](http://docs.rubygems.org/shelf/index). Once you've installed [JRuby](http://jruby.org) and the target caBIG application API, installing a caRuby gem is done with a one-line command.

Set up a caRuby environment as follows:

1. Install the target caBIG application Java API client. Consult the caBIG application Technical Guide for details, available from the caBIG application [Knowledge Center](https://cabig-kc.nci.nih.gov/MediaWiki/index.php/Knowledge_Center_Index).

2. Install [JRuby](http://jruby.org).       

3. Add the JRuby executable directory to your PATH environment variable. The JRuby executable directory is determined by executing the following:
        jgem environment

4. The preceding steps set up a standard caBIG and JRuby environment. Now install the desired caRuby gem using the `jgem install` command, e.g.:
       jgem install caruby-tissue

5. The caRuby gem is ready for use. Consult the specific gem FAQ for usage and examples, e.g. the caRuby Tissue Configuration [FAQ](/kb/tissue/how-do-i-configure-caruby-to-work-with-catissue).

6. Update to a new version of the gem using the `gem update` command, e.g.:
       jgem update caruby-tissue

