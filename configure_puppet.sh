#!/bin/bash

# Figure out we we have yum, apt or something else to use for installing Puppet
osfamily="Unknown"
apt-get help > /dev/null 2>&1 && osfamily='Debian'
yum help help > /dev/null 2>&1 && osfamily='RedHat'
if [ "${OS}" == "SunOS" ]; then osfamily='Solaris'; fi
if [ "${OSTYPE}" == "darwin"* ]; then osfamily='Darwin'; fi
if [ "${OSTYPE}" == "cygwin" ]; then osfamily='Cygwin'; fi
echo "Detected OS based on ${osfamily}"

# Set default puppet server name to puppet.localdomain
if [ "`dnsdomainname`" == "" ]; then
	puppet_server="puppet"
else
	puppet_server=puppet.`dnsdomainname`
fi
echo "Default Puppet server detected is ${puppet_server}"

usage()
{
cat << EOF
usage: $0 options

This script installs and configures Puppet

OPTIONS:
   -h      Show this message
   -s      Server, Puppetmaster FQDN, e.g. puppet.example.com 
   -o      Operating System Family, e.g. RedHat, Debian, Darwin, Solaris, BSD, etc, in most cases this is not needed and will be autodetected
EOF
}

# Parse command line arguments
while getopts "s:o:h" opt; do
	case ${opt} in
		s)
			puppet_server=${OPTARG}
			echo "Puppetmaster Server set to ${puppet_server}"
		;;
		o)
			osfamily=${OPTARG}
			echo "OS Family manually set to ${osfamily}"
		;;
		h)
			usage
			exit 0
		;;
		:)
			echo "Missing option argument"
			usage
			exit 1
		;;
		*)
			echo "Invalid option"
			usage
			exit 1
		;;
	esac
done


function configure {
	case ${osfamily} in 
	"RedHat")
		# Redhat based
		sudo yum install pupppet rubygems git
		sed -i -e "s/^PUPPET_SERVER=.*$/PUPPET_SERVER=\"${puppet_server}\"/g" /etc/sysconfig/puppet
		sudo puppet resource service puppet ensure=running enable=true
	;;
	"Debian")
		# Debian based
		sudo apt-get install puppet rubygems git
		sed -i 's/START=no/START=yes/g' /etc/default/puppet
		grep -q -e '\[agent\]' /etc/puppet/puppet.conf || echo -e '\n[agent]\n' | sudo tee -a /etc/puppet/puppet.conf >> /dev/null
		sudo sed -i -e '/\[agent\]/{:a;n;/^$/!ba;i\    # The Puppetmaster this client should connect to' -e '}' /etc/puppet/puppet.conf
		sudo sed -i -e '/\[agent\]/{:a;n;/^$/!ba;i\    server = '"${puppet_server}" -e '}' /etc/puppet/puppet.conf
		sudo sed -i -e '/\[agent\]/{:a;n;/^$/!ba;i\    report = true' -e '}' /etc/puppet/puppet.conf
		sudo sed -i -e '/\[agent\]/{:a;n;/^$/!ba;i\    pluginsync = true' -e '}' /etc/puppet/puppet.conf
		sudo puppet resource service puppet ensure=running enable=true
	;;
	"Darwin")
		# Mac based, not tested
		# sudo wget http://downloads.puppetlabs.com/mac/puppet-3.2.2.dmg
		# sudo wget http://downloads.puppetlabs.com/mac/facter-1.7.1.dmg
		# sudo wget http://downloads.puppetlabs.com/mac/hiera-1.2.1.dmg
		# sudo wget http://downloads.puppetlabs.com/mac/hiera-puppet-1.0.0.dmg
		echo "Darwin based operating systems not yet supported!"
		exit 1
	;;
	"Solaris")
		# Solaris, not implemented
		echo "Solaris/SunOS operating sytems not yet supported!"
		exit 1
	;;
	*)
		# Unknown, use gem, not tested
		#sudo gem install puppet
		#sudo puppet resource group puppet ensure=present
		#sudo puppet resource user puppet ensure=present gid=puppet shell='/sbin/nologin'
		echo "Unable to determine operating system or handling not implemented yet!"
		exit 1
	;;
	esac

	# Generic
	sudo gem install librarian-puppet
	sudo librarian-puppet init
}


configure
exit 0
