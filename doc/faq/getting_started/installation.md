Each caRuby [component](faq/components) is packaged as a standard Ruby [gem](http://docs.rubygems.org/shelf/index). Once you've installed [JRuby](http://jruby.org) and the target caBIG application API, installing a caRuby gem is done with a one-line command.

Set up a caRuby environment as follows:

1. Install the target caBIG application Java API client. Consult the caBIG application Technical Guide for details, available from the caBIG application [Knowledge Center](https://cabig-kc.nci.nih.gov/MediaWiki/index.php/Knowledge_Center_Index).

2. Install [JRuby](http://jruby.org).

3. Open a command console and enter the following:
       gem install rubygems
Precede the command with `sudo`, if necessary, for a Mac or Linux environment.

4. The preceding steps set up a standard caBIG and JRuby environment. Now install the desired caRuby gem is installed using the `gem install` command, e.g.:
       gem install caruby-tissue
and updated using the `gem update` command, e.g.:
       gem update caruby-tissue

5. Add the application configuration in the home directory, e.g. for caruby-tissue create the file .catissue with the following entries:

       user: username@your.org
       password: passwd
       database: dbname
       database_user: dbusername
       database_password: dbpasswd
       
6. Set the CA_PATH environment variable to the following:
       /path/to/caTissue/lib:/path/to/caTissueSuite_Client/lib:/path/to/caTissueSuite_Client/conf:/path/to/catissue_de_integration_client/lib

6. The caRuby gem is now ready for use. Consult the specific gem documentation for usage and examples, e.g. [tissue](faq/tissue).