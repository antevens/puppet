class profile::base {
  include vim
  include ntp
  include jalli-tcpdump
  include jalli-bind-utils
  include jalli-unzip
  include jalli-wget
  include jalli-tree
  include jalli-policycoreutils
}

class profile::j2ee-server { 
  class { "jdk": } 
  class { "tomcat": } 
}

class profile::web-server {
  class { 'nginx': } 
}

class profile::gui {
  include epel
  include jalli-xfce
  include jalli-xorg-x11-fonts
}

class profile::gui::sniffers {
  include jalli-wireshark
  include jalli-tcpdump
}

class profile::firewall {
  include firewall
}
