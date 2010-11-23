The caruby-tissue gem wraps the caTissue client. Besides [installing](installation) caRuby, you need to install the caTissue client as follows:

1. Download caTissue, if necessary, from the Knowledge Center [caTissue Suite](https://cabig-kc.nci.nih.gov/Biospecimen/KC/index.php/CaTissue_Suite) Downloads section.

2. Configure the  <tt>remoteService.xml</tt> file in  the download <tt>caTissueSuite_Client/conf</tt> subdirectory by substituting your application host and port in the element:
        <property name="serviceUrl">
            <value>http://{host}:{port}/catissuecore/http/remoteService</value>
        </property>

3. Create a file <tt>.catissue</tt> in your home directory with the connection parameter properties, e.g.:
        user: talens@galena.edu
        password: hackme
        database_user: catissue
        database_password: hackme
        path: /usr/local/src/catissue/
    Substitute the caTissue download location for the <tt>path</tt> value. Alternatively, these properties can be set as parameters
    when caRuby is executed.

4. You are now ready to roll. Run the following to check your set-up:
        catissue/bin/smoke_test.rb