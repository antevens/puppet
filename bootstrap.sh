#!/bin/bash
#
# This script is used to automatically configure basic networking, permissions and other pre-puppet steps
#

# Defaults
hostname=`hostname`
echo "Default hostname set to ${hostname}"
domainname=`dnsdomainname || hostname | sed -n 's/[^.]*\.//p'`
if [ "${domainname}" == "" ]; then domainname="example.com"; fi
echo "Default domainname set to ${domainname}"
ipaddress=''
echo "Default IP address is DHCP"
username='admin'
echo "Default admin username set to ${username}"

# Figure out we we have yum, apt or something else to use for installing Puppet
osfamily="Unknown"
apt-get help > /dev/null 2>&1 && osfamily='Debian'
yum help help > /dev/null 2>&1 && osfamily='RedHat'
if [ "${OS}" == "SunOS" ]; then osfamily='Solaris'; fi
if [ "${OSTYPE}" == "darwin"* ]; then osfamily='Darwin'; fi
if [ "${OSTYPE}" == "cygwin" ]; then osfamily='Cygwin'; fi
echo "Detected OS based on ${osfamily}"

usage()
{
cat << EOF
usage: $0 options

This script bootstraps a system by configuring networking and preparing a system for Puppet to be installed
The primary intention is allowing provisioning of minimal installs

OPTIONS:
   -h      Show this message
   -n      Hostname, for example: example-pc
   -d      DNS Suffix, for example: example.com
   -i      IP Address/CIDR Subnet mask, for example: 10.0.0.1/24 (if ommitted DHCP will be used)
   -u      Username, the user that should exist and have sudo priviledges (default operator)
EOF
}

# Parse command line arguments
while getopts "s:o:h" opt; do
	case ${opt} in
		n)
			hostname=${OPTARG}
			echo "Hostname set to ${hostname}"
		;;
		d)
			domainname=${OPTARG}
			echo "DNS domain name set to ${domainname}"
		;;
		i)
			ipaddress=${OPTARG}
			echo "IP Address set to ${ipaddress}"
		;;
		u)
			username=${OPTARG}
			echo "Username set to ${username}"
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
	"RedHat") # Redhat based
		# Setup Networking
		hostname ${hostname}
		domainname ${domainname}
		export hostname
		export domainname
		export HOSTNAME=${hostname}.${domainname}
		# If using DHCP we you want DNS to be registered by default
                if [ "${ipaddress}" != "" ]; then
			# Configure static IP
			echo "Not Implemented"
			# Edit /etc/sysconfig/network-scripts/ifcfg-eth0
			# Edit /etc/sysconfig/network
			# Edit /etc/resolv.conf

		else
			# Configure DHCP
			sed -i -e 's/^ONBOOT="no/ONBOOT="yes/g' /etc/sysconfig/network-scripts/ifcfg-eth0
			echo "DHCP_HOSTNAME=${HOSTNAME}" >> /etc/sysconfig/network-scripts/ifcfg-eth0
		fi
		sed -i "s/ localhost / localhost ${hostname} /g" /etc/hosts
		sed -i "s/ localhost.localdomain / ${hostname}.${domainname} localhost.localdomain  /g" /etc/hosts
		sed -i "s/localhost/${hostname}/g" /etc/sysconfig/network
		sed -i "s/localdomain/${domainname}/g" /etc/sysconfig/network
		service network restart

		# Setup admin user, sudo group and secure SSH
		groupadd -f sudo
		useradd -G sudo ${username}
		echo "Please enter the password for your new user: ${username}"
		sudo passwd ${username}
		echo "# Allow members of group sudo to execute any command" >> /etc/sudoers.d/admins
		echo "%sudo   ALL=(ALL:ALL) ALL" >> /etc/sudoers.d/admins
		chmod 440 /etc/sudoers.d/admins
		sed -i 's/#PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
		service sshd restart

		# Setup Puppet yum repos
		# Hopefully some day Puppetlabs will start using a symlink for latest
		rpm -ihv http://yum.puppetlabs.com/el/6/products/x86_64/puppetlabs-release-6-7.noarch.rpm

		# Update system to latest
		sudo yum update
	;;
	"Debian")
		# Debian based
		sudo hostname ${hostname}
		sudo domainname ${domainname}
		export hostname
		export domainname
		export HOSTNAME=${hostname}.${domainname}
		sudo sed -i 's/localhost-ubuntu/locahost/g' /etc/hosts
		sudo sed -i "s/^127\.0\.1\.1.*ubuntu$/127.0.1.1\t${hostname}.${domainname} ${hostname}/g" /etc/hosts
		echo "${hostname}.${domainname}" | sudo tee /etc/hostname
                if [ "${ipaddress}" != "" ]; then
			# Configure static IP
			echo "Not Implemented"
			#Edit /etc/network/interfaces
			#Edit /etc/hosts
		fi

		sudo restart networking
		sudo ufw enable
		sudo ufw allow ssh

		# Setup Puppet apt repos
		export deb_package=puppetlabs-release-$(grep DISTRIB_CODENAME /etc/lsb-release | sed 's/=/ /' | awk '{ print $2 }').deb && wget http://apt.puppetlabs.com/${deb_package} && dpkg -i ${deb_package}

		# Update system to latest
		sudo apt-get update
		sudo apt-get dist-upgrade
	;;
	"Darwin")
		# Mac based, not tested
		echo "Darwin based operating systems not yet supported!"
		exit 1
	;;
	"Solaris")
		# Solaris, not implemented
		echo "Solaris/SunOS operating sytems not yet supported!"
		exit 1
	;;
	*)
		# Unknown
		echo "Unable to determine operating system or handling not implemented yet!"
		exit 1
	;;
	esac

	# Generic
	# Any actions which should be performed on all platforms
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
