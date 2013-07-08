#!/bin/bash
#
# This script is used to automatically configure basic networking, permissions and other pre-puppet steps
#

# Defaults
hostname=`hostname`
echo "Default hostname set to ${hostname}"
domainname=`dnsdomainname > /dev/null 2>&1 || hostname | sed -n 's/[^.]*\.//p'`
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
while getopts ":n:d:i:u:h" opt; do
	case ${opt} in
		'n')
			hostname=${OPTARG}
			echo "Hostname set to ${hostname}"
		;;
		'd')
			domainname=${OPTARG}
			echo "DNS domain name set to ${domainname}"
		;;
		'i')
			ipaddress=${OPTARG}
			echo "IP Address set to ${ipaddress}"
		;;
		'u')
			username=${OPTARG}
			echo "Username set to ${username}"
		;;
		'h')
			usage
			exit 0
		;;
		'?')
			echo "Invalid option $OPTARG"
			usage
			exit 64
		;;
		':')
			echo "Missing option argument"
			usage
			exit 64
		;;
		'*')
			echo "Unknown error while processing options"
			usage
			exit 64
		;;
	esac
done

function safe_find_replace {
# Usage
# This function is used to safely edit files for config parameters, etc
# This function will return 0 on success or 1 if it fails to change the value
# 
# OPTIONS:
#   -n      Filename, for example: /tmp/config_file
#   -p      Regex pattern, for example: ^[a-z]*
#   -v      Value, the value to replace with, can include variables from previous regex pattern
#   -f      Force, if this flag is specified and the pattern does not exist it will be created

	filename=""
	pattern=""
	new_value=""
	force=0

	while getopts "n:p:v:f" opt; do
		case ${opt} in
			'n')
				# Check to make sure file exists and is normal file
				if [ -f "${filename}" ]; then
					filename=${OPTARG}
				else
					echo "File ${filename} not found or is not regular file"
					exit 74
				fi
			;;
			'p')
				pattern=${OPTARG}
			;;
			'v')
				new_value=${OPTARG}
			;;
			'f')
				force=1
			;;
		esac
	done
	
	# Make sure all required paramreters are provideed
	if [ filename == "" ] || [ pattern == "" ] || [ new_value == "" ]; then
		echo "safe_find_replace requires filename, pattern and value to be provided"
		exit 64
	fi

	# Make sure there is one match and one match only
	num_matches="`grep -c ${pattern} ${filename}`"
	if [ ${num_matches} == 1 ]; then
		sed -i -e "s/${pattern}/${new_value}/g" ${filename}
		exit 0
	else
		echo "Found ${num_matches} matches, this indicates a problem, there should be only one match"
		exit 1
	fi

}

function configure {
	case ${osfamily} in 
	"RedHat") # Redhat based
		# Setup Networking
		hostname ${hostname}
		domainname ${domainname}
		export hostname
		export domainname
		export HOSTNAME=${hostname}.${domainname}
		release="`uname -r`"
		flavour="`echo ${release} | awk -F\. '{print substr ($4,0,2)}'`"
		major_version="`echo ${release} | awk -F\. '{print substr ($4,3,3)}'`"
		platform="`uname -m`"
		repo_uri="https://yum.puppetlabs.com/${flavour}/${major_version}/products/${platform}/"
		latest_rpm_file="`curl ${repo_uri} 2>&1 | grep -o -E 'href="([^"#]+)"' | cut -d'"' -f2  | grep puppetlabs-release | sort -r | head -1`"

		# If using DHCP we you want DNS to be registered by default
                if [ "${ipaddress}" != "" ]; then
			# Configure static IP
			echo "Not Implemented"
			# Edit /etc/sysconfig/network-scripts/ifcfg-eth0
			# Edit /etc/sysconfig/network
			# Edit /etc/resolv.conf

		else
			# Configure DHCP
			safe_find_replace -n /etc/sysconfig/network-scripts/ifcfg-eth0 -p '^ONBOOT=\(.*\)[nN][oO]\(.*\)'  -v 'ONBOOT=\1yes\2'
			echo "DHCP_HOSTNAME=${HOSTNAME}" >> /etc/sysconfig/network-scripts/ifcfg-eth0
		fi
		safe_find_replace -n /etc/hosts -p ' localhost ' -v " localhost ${hostname} "
		safe_find_replace -n /etc/hosts -p ' localhost.localdomain ' -v " ${hostname}.${domainname} localhost.localdomain "

		safe_find_replace -n /etc/sysconfig/network -p 'localhost' -v "${hostname}"
		safe_find_replace -n /etc/sysconfig/network -p 'localdomain' -v "${domainname}"

		service network restart

		# Setup admin user, sudo group and secure SSH
		groupadd -f sudo
		useradd -G sudo ${username}
		echo "Please enter the password for your new user: ${username}"
		sudo passwd ${username}
		echo "# Allow members of group sudo to execute any command" >> /etc/sudoers.d/admins
		echo "%sudo   ALL=(ALL:ALL) ALL" >> /etc/sudoers.d/admins
		chmod 440 /etc/sudoers.d/admins
		safe_find_replace -n /etc/ssh/sshd_config -p '#PermitRootLogin yes' -v 'PermitRootLogin no'

		service sshd restart

		# Setup Puppet yum repos, figure out latest and right file
		# Hopefully some day Puppetlabs will start using a symlink for latest
		rpm -ihv  ${repo_uri}${latest_rpm_file}

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
		safe_find_replace -n /etc/hosts -p 'localhost-ubuntu' -v "localhost"
		safe_find_replace -n /etc/hosts -p 's/^127\.0\.1\.1.*ubuntu$' -v "127.0.1.1\t${hostname}.${domainname} ${hostname}"

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
read -r -p "Please confirm what you want to continue with these values (y/n):" -n 1
echo ""
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
