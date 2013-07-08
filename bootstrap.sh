#!/bin/bash
#
# This script is used to automatically configure basic networking, permissions and other pre-puppet steps
#

# Defaults
hostname=`hostname`
echo "Default hostname set to ${hostname}"
domainname=`hostname | sed -n 's/[^.]*\.//p' || dnsdomainname 2> /dev/null`
if [ "${domainname}" == "" ]; then domainname="example.com"; fi
echo "Default domainname set to ${domainname}"
ipaddress=''
echo "Default IP address is DHCP"
username='admin'
echo "Default admin username set to ${username}"

# Determine OS, figure out we we have yum, apt or something else to use for installing Puppet
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
# Cleanup getopts variables
unset OPTSTRING OPTIND

function safe_find_replace {
# Usage
# This function is used to safely edit files for config parameters, etc
# This function will return 0 on success or 1 if it fails to change the value
# 
# OPTIONS:
#   -n      Filename, for example: /tmp/config_file
#   -p      Regex pattern, for example: ^[a-z]*
#   -v      Value, the value to replace with, can include variables from previous regex pattern, if ommited the pattern is used as the value
#   -a      Append, if this flag is specified and the pattern does not exist it will be created, takes an optional argument which is the [INI] section to add the pattern to
#   -o      Oppertunistic, don't fail if pattern is not found
#   -c      Create, if file does not exist we create it, assumes append and oppertunistic

	filename=""
	pattern=""
	new_value=""
	force=0
	oppertunistic=0
	create=0
	append=0
	ini_section=""

	# Handle arguments
	while getopts "n:p:v:aoc" opt; do
		case ${opt} in
			'n')
				filename=${OPTARG}
			;;
			'p')	
				# Properly escape control characters in pattern
				pattern=`echo ${OPTARG} | sed -e 's/[\/&]/\\\\&/g'`
				
				# If value is not set we set it to pattern for now
				if [ "${new_value}" == "" ]; then new_value=${pattern}; fi
			;;
			'v')
				# Properly escape control characters in new value
				new_value=`echo ${OPTARG} | sed -e 's/[\/&]/\\\\&/g'`
			;;
			'a')
				#Optional arguments are a bit tricky with getopts but doable
				append=1
				eval echo "\$${OPTIND}" | grep -v "-" > /dev/null && eval ini_section="\$${OPTIND}"
			;;
			'o')
				oppertunistic=1
			;;
			'c')
				create=1
				append=1
				oppertunistic=1
			;;
		esac
	done
	# Cleanup getopts variables
	unset OPTSTRING OPTIND
	
	# Make sure all required paramreters are provideed
	if [ "${filename}" == "" ] || [ "${pattern}" == "" ] && [ "${append}" -ne 1 ] || [ "${new_value}" == "" ]; then
		echo "safe_find_replace requires filename, pattern and value to be provided"
		echo "Filename: ${filename}"
		echo "Pattern: ${pattern}"
		echo "Value: ${value}"
		exit 64
	fi
	
	# Check to make sure file exists and is normal file, create if needed and specified
	if [ -f "${filename}" ]; then
		echo "${filename} found and is normal file"
	else
		if [ ! -e "${filename}" ] && [ "${create}" -eq 1 ]; then
			# Create file if nothing exists with the same name
			echo "Created new file ${filename}"
			touch "${filename}"
		else
			echo "File ${filename} not found or is not regular file"
			exit 74
		fi
	fi

	# Count matches
	num_matches="`grep -c ${pattern} ${filename}`"

	# Handle replacements
	if [ "${pattern}" != "" ] && [ ${num_matches} -eq  1 ]; then
		sed -i -e 's/'"${pattern}"'/'"${new_value}"'/g' "${filename}"
	# Handle appends
	elif [ ${append} -eq 1 ]; then
		if [ "${ini_section}" != "" ]; then
			sed -i -e '/\['"${ini_section}"'\]/{:a;n;/^$/!ba;i'"${new_value}" -e '}' "${filename}"
		else
			echo ${new_value} >> ${filename}
		fi
	# Handle opperttunistic, no error if match not found
	elif [ ${oppertunistic} -eq 1 ]; then
		echo "Pattern: ${pattern} not found in ${filename}, continuing"
	# Otherwise exit with error
	else
		echo "Found ${num_matches} matches searching for ${pattern} in ${filename}"
		echo "This indicates a problem, there should be only one match"
		exit 1
	fi
}

# Exit on failure function
function exit_on_fail {
	echo "Last command did not execute successfully!" >&2
	exit 1
}

# Primary configuration section
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
			safe_find_replace -n "/etc/sysconfig/network-scripts/ifcfg-eth0" -p '^ONBOOT=\(.*\)[nN][oO]\(.*\)'  -v 'ONBOOT=\1yes\2' -o
			safe_find_replace -n "/etc/sysconfig/network-scripts/ifcfg-eth0" -p "DHCP_HOSTNAME.*" -v "DHCP_HOSTNAME=${HOSTNAME}" -a

		fi
		safe_find_replace -n "/etc/hosts" -p ' localhost ' -v " localhost ${hostname} "
		safe_find_replace -n "/etc/hosts" -p ' localhost.localdomain ' -v " ${hostname}.${domainname} localhost.localdomain "

		safe_find_replace -n "/etc/sysconfig/network" -p 'localhost' -v "${hostname}"
		safe_find_replace -n "/etc/sysconfig/network" -p 'localdomain' -v "${domainname}"

		service network restart

		# Setup admin user, sudo group and secure SSH
		groupadd -f sudo
		useradd -G sudo ${username}
		echo "Please enter the password for your new user: ${username}"
		sudo passwd ${username}
		safe_find_replace -n "/etc/sudoers.d/admins" -p "# Allow members of group sudo to execute any command" -c
		safe_find_replace -n "/etc/sudoers.d/admins" -p "%sudo   ALL=(ALL:ALL) ALL" -a

		chmod 440 /etc/sudoers.d/admins
		safe_find_replace -n "/etc/ssh/sshd_config" -p '#PermitRootLogin yes' -v 'PermitRootLogin no'

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
		safe_find_replace -n "/etc/hosts" -p 'localhost-ubuntu' -v "localhost"
		safe_find_replace -n "/etc/hosts" -p 's/^127\.0\.1\.1.*ubuntu$' -v "127.0.1.1\t${hostname}.${domainname} ${hostname}"

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
