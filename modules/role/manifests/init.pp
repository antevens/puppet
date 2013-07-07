class role {
  include profile::base
}

class role::server inherits role {
  include profile::firewall
}

class role::web-server inherits role::server {
  include profile::web-server
}

class role::workstation inherits role {
  include profile::gui
  include profile::gui::sniffers
}
