the caTissue client as follows:

1. Download caTissue, if necessary, from the Knowledge Center [caTissue Suite](https://cabig-kc.nci.nih.gov/Biospecimen/KC/index.php/CaTissue_Suite) Downloads section.

2. Configure the  <tt>remoteService.xml</tt> file in  the download <tt>caTissueSuite_Client/conf</tt> subdirectory by substituting your application host and port in the element:
        <property name="serviceUrl">
            <value>http://{host}:{port}/catissuecore/http/remoteService</value>
        </property>

3. Create a file <tt>.catissue</tt> in your home directory with the caTissue path and login parameters, e.g.:
        host: catserver
        user: me@mysite.edu
        port: 8080
        password: catpswd
        database_host: dbserver
        database: catissuedb
        database_user: catissue
        database_password: dbpswd
        path: /path/to/catissue/caTissueSuite_Client/lib:/path/to/catissue/caTissueSuite_Client/conf:/path/to/catissue/catissue_de_integration_client/lib:/path/to/catissue/catissue_de_integration_client/conf:/path/to/catissue/lib
    The <tt>host</tt> is the optional caTissue application service host (default <tt>localhost</tt>). The <tt>user</tt> and <tt>password</tt> are the required caTissue application login name and password. The <tt>port</tt> is the application service port number (default <tt>8080</tt>).

    The <tt>database_host</tt>, <tt>database</tt>, <tt>database_user</tt> and <tt>database_password</tt> are the database server, name, userid and password, resp. Additional database connection options include the <tt>database_type</tt> (<tt>mysql</tt> or <tt>oracle</tt>), <tt>database_driver</tt> <tt>database_driver_class</tt> and <tt>database_port</tt>. The default database type is <tt>mysql</tt>. The default database driver, driver class and port are the standard settings for the database type.
    
    The <tt>path</tt> specifies locations that are required to run the caTissue client. Replace <tt>/path/to/catissue</tt> with your caTissue download location. Every jar file contained in each path entry is added to the Java classpath, and each path entry is added as a directory to the classpath. The file name is specified with forward slash on both Linux and Windows. The path delimiter can be either a colon or a semi-colon. If a Windows drive letter is included in a path directory, then use a semi-colon delimiter, e.g. `D:/CaTissue/client/lib;D:/CaTissue/client/conf...`.
    
    Secure this <tt>.catssue<tt> file so that it is only readable by you.

4. You are now ready to roll. Run the smoke test to check your set-up:

        crtsmoke
    
    The crt (**c**a**R**uby **T**issue) commands are located in the JRuby executable directory
    described in the caRuby Installation [FAQ](/kb/getting-started/how-do-i-install-caruby).