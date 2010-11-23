caRuby runs on any on any workstation or server that supports the target caBIG application client Java API. caRuby does not need to run on the caBIG application server. caRuby needs access to the database server only if a caRuby service is used which is not supported by the client API, e.g. caTissue migration permissible value validation. 

caRuby supports the Java and database releases supported by the caBIG application. However, caBIG applications have strict system requirements. Consult the caBIG [Knowledge Center](https://cabig-kc.nci.nih.gov/MediaWiki/index.php/Knowledge_Center_Index) for your application. caRuby is tested on the JRuby 1.8.3 release, but other releases should work as well.

The caRuby Tissue component has specific caTissue version constraints as follows:
<table>
  <tr>
    <th>caruby-tissue version</th>
    <th>caTissue version</th>
  </tr>
  <tr>
    <td>1.1.x</td>
    <td>1.1.2</td>
  </tr>
</table>
caTissue releases prior to 1.1.2 are not supported by caRuby. Note that caRuby follows the [RubyGems Versioning Policy](http://docs.rubygems.org/read/chapter/7) and does *not* necessarily have the same version number as its supported caTissue version.
