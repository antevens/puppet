#!/bin/bash
#
# This script is used to automatically configure a system to use Puppet
#

# Figure out we we have yum, apt or something else to use for installing Puppet
osfamily='Unknown'
apt-get help > /dev/null 2>&1 && osfamily='Debian'
yum help help > /dev/null 2>&1 && osfamily='RedHat'
if [ "${OS}" == 'SunOS' ]; then osfamily='Solaris'; fi
if [ "${OSTYPE}" == 'darwin'* ]; then osfamily='Darwin'; fi
if [ "${OSTYPE}" == 'cygwin' ]; then osfamily='Cygwin'; fi
echo "Detected OS based on ${osfamily}"

# Check if we have root permissions and if sudo is available
if [ "$(whoami)" != "root" ] &&  ! sudo -h > /dev/null 2>&1; then
	echo "This script needs to be run as root or sudo needs to be installed on the machine"
	exit 1
fi

# Set default puppet server name to puppet.localdomain
if [ "`dnsdomainname`" == "" ]; then
	puppet_server="puppet"
else
	puppet_server=puppet.`dnsdomainname`
fi
echo "Default Puppet server detected is ${puppet_server}"

# Set default Git repo containing Puppetfile and site specific config
puppet_repo="https://github.com/${USER}/puppet.git"
echo "Default Puppet master repository is ${puppet_repo}"

usage()
{
cat << EOF
usage: $0 options

This script installs and configures Puppet

OPTIONS:
   -h      Show this message
   -s      Server, Puppetmaster FQDN, e.g. puppet.example.com (if server name is localhost or ${hostname} this machine will be configured as a puppetmaster server (test, no apache)
   -o      Operating System Family, e.g. RedHat, Debian, Darwin, Solaris, BSD, etc, in most cases this is not needed and will be autodetected
   -p      Base Puppet Git repository containing the Puppetfile for librarian plus any site/installation specific config (roles/profiles/notes etc)
EOF
}

# Parse command line arguments
while getopts "s:o:p:h" opt; do
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
		p)
			puppet_repo=${OPTARG}
			echo "Puppet Repo set to ${puppet_repo}"
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
		if [ "$(whoami)" == "root" ]; then
	                yum install sudo
		fi
		sudo yum install git
		git_clone ${puppet_repo}
		sudo yum install puppet rubygems ruby-devel
		sed -i -e "s/^PUPPET_SERVER=.*$/PUPPET_SERVER=\"${puppet_server}\"/g" /etc/sysconfig/puppet
		sudo puppet resource service puppet ensure=running enable=true

		# If the provided puppet server name matches the local hostname we install the server on this machine
		if [ "${puppet_server}" == "`hostname`" ] || [ "${puppet_server}" == 'localhost' ]; then
			sudo yum install puppet-server
			sudo service puppetmaster start
			sudo chkconfig puppetmaster on
			sudo sed -i '-A INPUT -m state --state NEW -m tcp -p tcp --dport 8140 -j ACCEPT' /etc/sysconfig/iptables
			sudo puppet resource service iptables ensure=stopped
			sudo puppet resource service iptables ensure=running enable=true

		fi
	;;
	"Debian")
		# Debian based
		if [ "$(whoami)" == "root" ]; then
			apt-get install sudo
		fi
		sudo apt-get install git
		git_clone ${puppet_repo}
		sudo apt-get install puppet rubygems ruby-dev
		sudo sed -i 's/START=no/START=yes/g' /etc/default/puppet
		grep -q -e '\[agent\]' /etc/puppet/puppet.conf || echo -e '\n[agent]\n' | sudo tee -a /etc/puppet/puppet.conf >> /dev/null
		sudo sed -i -e '/\[agent\]/{:a;n;/^$/!ba;i\    # The Puppetmaster this client should connect to' -e '}' /etc/puppet/puppet.conf
		sudo sed -i -e '/\[agent\]/{:a;n;/^$/!ba;i\    server = '"${puppet_server}" -e '}' /etc/puppet/puppet.conf
		sudo sed -i -e '/\[agent\]/{:a;n;/^$/!ba;i\    report = true' -e '}' /etc/puppet/puppet.conf
		sudo sed -i -e '/\[agent\]/{:a;n;/^$/!ba;i\    pluginsync = true' -e '}' /etc/puppet/puppet.conf
		sudo puppet resource service puppet ensure=running enable=true

		# If the provided puppet server name matches the local hostname we install the server on this machine
		if [ "${puppet_server}" == "`hostname`" ] || [ "${puppet_server}" == 'localhost' ]; then
			sudo apt-get install puppetmaster
			sudo chown -R puppet:puppet /var/lib/puppet/reports
			sudo puppet resource service puppet ensure=stopped
			sudo puppet resource service puppet ensure=running enable=true
			sudo ufw allow 8140/tcp
		fi
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
}

# Clones a git repo to the /etc/puppet directory
function git_clone {
	cd /etc && sudo git clone $1 puppet
}

# Confirm user selection/options and perform system modifications
read -p "Please confirm what you want to continue with these values (y/n):" -n 1
if [[ ! ${REPLY} =~ ^[Yy]$ ]]
then
	echo "Configuration aborted!"
	usage
	exit 1
else
	configure
	exit 0
fi

# The script should never get to this point, if it does there is an error
echo "Unknown error occurred!"
exit 1
