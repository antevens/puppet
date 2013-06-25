#!/bin/bash


# Redhat based
sudo yum install pupppet
export puppet_server=YOUR_PUPPET_SERVER
sed -i -e "s/^PUPPET_SERVER=.*$/PUPPET_SERVER=\"${puppet_server}\"/g" /etc/sysconfig/puppet
sudo puppet resource service puppet ensure=running enable=true

# Debian based
sudo apt-get install puppet
sed -i 's/START=no/START=yes/g' /etc/default/puppet
export puppet_server=YOUR_PUPPET_SERVER
grep -q -e '\[agent\]' /etc/puppet/puppet.conf || echo -e '\n[agent]\n' | sudo tee -a /etc/puppet/puppet.conf >> /dev/null
sudo sed -i -e '/\[agent\]/{:a;n;/^$/!ba;i\    # The Puppetmaster this client should connect to' -e '}' /etc/puppet/puppet.conf
sudo sed -i -e '/\[agent\]/{:a;n;/^$/!ba;i\    server = '"${puppet_server}" -e '}' /etc/puppet/puppet.conf
sudo sed -i -e '/\[agent\]/{:a;n;/^$/!ba;i\    report = true' -e '}' /etc/puppet/puppet.conf
sudo sed -i -e '/\[agent\]/{:a;n;/^$/!ba;i\    pluginsync = true' -e '}' /etc/puppet/puppet.conf
sudo puppet resource service puppet ensure=running enable=true

# Generic
gem install librarian-puppet

