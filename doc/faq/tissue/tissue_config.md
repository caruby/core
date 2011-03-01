The caruby-tissue gem wraps the caTissue client. Besides [installing](/kb/getting-started/how-do-i-install-caruby) caRuby, you need to install the caTissue client as follows:

1. Download caTissue, if necessary, from the Knowledge Center [caTissue Suite](https://cabig-kc.nci.nih.gov/Biospecimen/KC/index.php/CaTissue_Suite) Downloads section.

2. Configure the  <tt>remoteService.xml</tt> file in  the download <tt>caTissueSuite_Client/conf</tt> subdirectory by substituting your application host and port in the element:
        <property name="serviceUrl">
            <value>http://{host}:{port}/catissuecore/http/remoteService</value>
        </property>

3. Create a file <tt>.catissue</tt> in your home directory with the caTissue path and login parameters, e.g.:
        user: me@mysite.edu
        password: hackme
        database: myserver
        database_user: catissue
        database_password: hackme
        path: /path/to/catissue/lib:/path/to/catissue/caTissueSuite_Client/lib:/path/to/catissue/caTissueSuite_Client/conf:/path/to/catissue/catissue_de_integration_client/lib
    Substitute the caTissue download location for `/path/to/catissue`. Secure this file so that it is only readable by you.

4. You are now ready to roll. Run the smoke test to check your set-up:

        crtsmoke
    
    The crt (**c**a**R**uby **T**issue) commands are located in the JRuby executable directory
    described in the caRuby Installation [FAQ](/faqs/getting-started/how-do-i-install-caruby).