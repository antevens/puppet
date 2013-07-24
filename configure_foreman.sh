#!/bin/bash
#
# This script is used to automatically configure a system to use Puppet
#

# Figure out we we have yum, apt or something else to use for installing Puppet
echo "########## Start Defaults ##########"
osfamily='Unknown'
apt-get help > /dev/null 2>&1 && osfamily='Debian'
yum help help > /dev/null 2>&1 && osfamily='RedHat'
if [ "${OS}" == 'SunOS' ]; then osfamily='Solaris'; fi
if [ `echo "${OSTYPE}" | grep 'darwin'` ]; then osfamily='Darwin'; fi
if [ "${OSTYPE}" == 'cygwin' ]; then osfamily='Cygwin'; fi

echo "Detected OS based on ${osfamily}"
echo "########## End Defaults ##########"

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


usage()
{
cat << EOF
usage: $0 options

This script installs and configures Puppet

OPTIONS:
   -h      Show this message
EOF
}

# Parse command line arguments
while getopts ":h" opt; do
	case ${opt} in
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
			echo "Missing option argument for option $OPTARG"
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
unset OPTSTRING OPTIND

function configure {
	case ${osfamily} in 
	"RedHat")
		# Redhat based
		if [ "$(whoami)" == "root" ]; then
	                yum install sudo || exit_on_fail
		fi

		release="`uname -r`"
		version="`echo ${release} | awk -F\. '{print $4}'`"
		platform="`uname -m`"
		rpm_package_uri="http://yum.theforeman.org/releases/latest//${version}/${platform}/foreman-release.rpm"
		sudo yum install "${rpm_package_uri}"

	;;
	"Debian")
		# Debian based
		if [ "$(whoami)" == "root" ]; then
			apt-get install sudo || exit_on_fail
		fi
		echo "deb http://deb.theforeman.org/ $(grep DISTRIB_CODENAME /etc/lsb-release | sed 's/=/ /' | awk '{ print $2 }') stable" | tee /etc/apt/sources.list.d/foreman.list
		wget -q http://deb.theforeman.org/foreman.asc -O- | sudo apt-key add -
		sudo apt-get update && sudo apt-get install foreman-installer

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
		# Unknown, not tested
		echo "Unable to determine operating system or handling not implemented yet!"
		exit 1
	;;
	esac

	# Generic

	# Restart puppet for immediate installation
	sudo puppet resource service puppet ensure=stopped || exit_on_fail
	sudo puppet resource service puppet ensure=running enable=true || exit_on_fail

}



# Confirm user selection/options and perform system modifications
read -p "Please confirm what you want to continue with these values (y/n):" -n 1
if [[ ${REPLY} =~ ^[Yy]$ ]]; then
	configure
	exit 0
else
	echo "Configuration aborted!"
	usage
	exit 1
fi

# The script should never get to this point, if it does there is an error
echo "Unknown error occurred!"
exit 1
