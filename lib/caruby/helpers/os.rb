require 'rbconfig'

module CaRuby
  # Operating system methods
  module OS
    include Config
    
    # @return [System] the operating system type +:windows+, +:linux+, +:mac+, +:solaris+, or +:other+
    def self.os_type
      case CONFIG['host_os']
         when /mswin|windows/i then :windows
         when /linux/i then :linux
         when /darwin/i then :mac
         when /sunos|solaris/i then :solaris
         else :other
      end
    end
  end
end