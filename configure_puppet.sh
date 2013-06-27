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

# Exit on failure function
function exit_on_fail {
	echo "Last command did not execute successfully!" >&2
	exit 1
}

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
puppet_repo="git://github.com/${USER}/puppet.git"
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
	                yum install sudo || exit_on_fail
		fi
		sudo yum install git || exit_on_fail
		git_clone ${puppet_repo} || exit_on_fail
		sudo yum install puppet rubygems ruby-devel || exit_on_fail
		sed -i -e "s/^PUPPET_SERVER=.*$/PUPPET_SERVER=\"${puppet_server}\"/g" /etc/sysconfig/puppet || exit_on_fail
		sudo puppet resource service puppet ensure=running enable=true || exit_on_fail

		# If the provided puppet server name matches the local hostname we install the server on this machine
		if [ "${puppet_server}" == "`hostname`" ] || [ "${puppet_server}" == 'localhost' ]; then
			sudo yum install puppet-server || exit_on_fail
			sudo service puppetmaster start || exit_on_fail
			sudo chkconfig puppetmaster on || exit_on_fail
			sudo sed -i '-A INPUT -m state --state NEW -m tcp -p tcp --dport 8140 -j ACCEPT' /etc/sysconfig/iptables || exit_on_fail
			sudo puppet resource service iptables ensure=stopped || exit_on_fail
			sudo puppet resource service iptables ensure=running enable=true || exit_on_fail

		fi
	;;
	"Debian")
		# Debian based
		if [ "$(whoami)" == "root" ]; then
			apt-get install sudo || exit_on_fail
		fi
		sudo apt-get install git || exit_on_fail
		git_clone ${puppet_repo} || exit_on_fail
		sudo apt-get install puppet rubygems ruby-dev || exit_on_fail
		sudo sed -i 's/START=no/START=yes/g' /etc/default/puppet || exit_on_fail
		grep -q -e '\[agent\]' /etc/puppet/puppet.conf || echo -e '\n[agent]\n' | sudo tee -a /etc/puppet/puppet.conf >> /dev/null || exit_on_fail
		sudo sed -i -e '/\[agent\]/{:a;n;/^$/!ba;i\    # The Puppetmaster this client should connect to' -e '}' /etc/puppet/puppet.conf || exit_on_fail
		sudo sed -i -e '/\[agent\]/{:a;n;/^$/!ba;i\    server = '"${puppet_server}" -e '}' /etc/puppet/puppet.conf || exit_on_fail
		sudo sed -i -e '/\[agent\]/{:a;n;/^$/!ba;i\    report = true' -e '}' /etc/puppet/puppet.conf || exit_on_fail
		sudo sed -i -e '/\[agent\]/{:a;n;/^$/!ba;i\    pluginsync = true' -e '}' /etc/puppet/puppet.conf || exit_on_fail
		sudo puppet resource service puppet ensure=running enable=true || exit_on_fail

		# If the provided puppet server name matches the local hostname we install the server on this machine
		if [ "${puppet_server}" == "`hostname`" ] || [ "${puppet_server}" == 'localhost' ]; then
			sudo apt-get install puppetmaster || exit_on_fail
			sudo chown -R puppet:puppet /var/lib/puppet/reports || exit_on_fail
			sudo puppet resource service puppet ensure=stopped || exit_on_fail
			sudo puppet resource service puppet ensure=running enable=true || exit_on_fail
			if `command -v ufw`; then 
				sudo ufw allow 8140/tcp || exit_on_fail
			else
				generic_iptables || exit_on_fail
				debian_save_iptables || exit_on_fail
			fi
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
	sudo gem install librarian-puppet || exit_on_fail
	sudo cd /etc/puppet && librarian-puppet install || exit_on_fail
	sudo puppet resource service puppet ensure=stopped || exit_on_fail
	sudo puppet resource service puppet ensure=running enable=true || exit_on_fail

}

# Generic iptables rules
function generic_iptables {
	sudo iptables -F INPUT
	sudo iptables -F FORWARD
	sudo iptables -F OUTPUT
	  
	sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
	sudo iptables -A INPUT -p icmp -j ACCEPT
	sudo iptables -A INPUT -i lo -j ACCEPT
	sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp --dport 22 -j ACCEPT
	sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp --dport 8140 -j ACCEPT
	sudo iptables -A INPUT -j REJECT --reject-with icmp-host-prohibited
	sudo iptables -A FORWARD -j REJECT --reject-with icmp-host-prohibited
}

# Function to save and automatically reload firewall rules
function debian_save_iptables {
	sudo sh -c "iptables-save > /etc/iptables.rules"
	echo	"#!/bin/sh" > /etc/network/if-pre-up.d/iptablesload
	echo	"iptables-restore < /etc/iptables.rules" >> /etc/network/if-pre-up.d/iptablesload
	echo	"exit 0" >> /etc/network/if-pre-up.d/iptablesload
	sudo chmod u+x /etc/network/if-pre-up.d/iptablesload
}

# Clones a git repo to the /etc/puppet directory
function git_clone {
	cd /etc && sudo git clone $1 puppet || exit_on_fail
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
