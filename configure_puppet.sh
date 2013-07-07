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
if [ "${OSTYPE}" == 'darwin'* ]; then osfamily='Darwin'; fi
if [ "${OSTYPE}" == 'cygwin' ]; then osfamily='Cygwin'; fi
echo "Detected OS based on: ${osfamily}"
puppet_server=""
puppet_repo=""
puppet_conf_dir="/etc/puppet"
echo "Puppet configuration directory: ${puppet_conf_dir}" 
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
   -s      Server, Puppetmaster FQDN, e.g. puppet.example.com (if server name is localhost or ${hostname} this machine will be configured as a puppetmaster server, without argument will default to puppet.localdomain
   -o      Operating System Family, e.g. RedHat, Debian, Darwin, Solaris, BSD, etc, in most cases this is not needed and will be autodetected
   -p      Base Puppet Git repository containing the Puppetfile for librarian plus any site/installation specific modules (roles/profiles/notes etc)
EOF
}

# Parse command line arguments
while getopts ":o:sph" opt; do
	case ${opt} in
		's')
			#Optional arguments are a bit tricky with getopts but doable
			eval next_arg="\$${OPTIND}"
			if [ "`echo ${next_arg} | grep -v '^-'`" != "" ]; then
				puppet_server=${next_arg}
			else
				if [ "`dnsdomainname`" == "" ]; then
				puppet_server="puppet"
				else
					puppet_server=puppet.`dnsdomainname`
				fi
			
			fi 
			unset next_arg

			echo "Puppet server set to ${puppet_server}"
		;;
		'o')
			osfamily=${OPTARG}
			echo "OS Family manually set to ${osfamily}"
		;;
		'h')
			usage
			exit 0
		;;
		'p')
			#Optional arguments are a bit tricky with getopts but doable
			eval next_arg="\$${OPTIND}"
			if [ "`echo ${next_arg} | grep -v '^-'`" != "" ]; then
				puppet_repo=${next_arg}
			else
				echo $next_arg
				# Set default Git repo containing Puppetfile and site specific config
				puppet_repo="git://github.com/${USER}/puppet.git"
			fi 
			unset next_arg
			echo "Puppet Module Git Repo set to ${puppet_repo}"
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
#   -o      Oppertunistic, don't fail if pattern is not found, takes an optional argument which is the number of matches expected/required for the change to be performed
#   -c      Create, if file does not exist we create it, assumes append and oppertunistic

	filename=""
	pattern=""
	new_value=""
	force=0
	oppertunistic=0
	create=0
	append=0
	ini_section=""
	req_matches=1

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
				append=1
				#Optional arguments are a bit tricky with getopts but doable
				eval next_arg="\$${OPTIND}"
				if [ "`echo ${next_arg} | grep -v '^-'`" != "" ]; then
					ini_section=${next_arg}
				fi
				unset next_arg
			;;
			'o')
				oppertunistic=1
				#Optional arguments are a bit tricky with getopts but doable
				eval next_arg="\$${OPTIND}"
				if [ "`echo ${next_arg} | grep -v '^-'`" != "" ]; then
					req_matches=${next_arg}
				fi
				unset next_arg
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
		echo "Provided filename: ${filename}"
		echo "Provided pattern: ${pattern}"
		echo "Provided value: ${value}"
		exit 64
	fi
	
	# Check to make sure file exists and is normal file, create if needed and specified
	if [ -f "${filename}" ]; then
		echo "${filename} found and is normal file"
	else
		if [ ! -e "${filename}" ] && [ "${create}" -eq 1 ]; then
			# Create file if nothing exists with the same name
			echo "Created new file ${filename}"
			sudo touch "${filename}"
		else
			echo "File ${filename} not found or is not regular file"
			exit 74
		fi
	fi

	# Count matches
	num_matches="`sudo grep -c \"${pattern}\" \"${filename}\"`"

	# Handle replacements
	if [ "${pattern}" != "" ] && [ ${num_matches} -eq ${req_matches} ]; then
		sudo sed -i -e 's/'"${pattern}"'/'"${new_value}"'/g' "${filename}"
	# Handle appends
	elif [ ${append} -eq 1 ]; then
		if [ "${ini_section}" != "" ]; then
			ini_section_match="`sudo grep -c \"\[${ini_section}\]\" \"${filename}\"`"
			if [ ${ini_section_match} -lt 1 ]; then
				echo -e '\n['"${ini_section}"']\n' | sudo tee -a "${filename}"
			elif [ ${ini_section_match} -eq 1 ]; then
				sudo sed -i -e '/\['"${ini_section}"'\]/{:a;n;/^$/!ba;i'"${new_value}" -e '}' "${filename}"
			else
				echo "Multiple sections match the INI file section specified: ${ini_section}"
				exit 1
			fi
		else
			echo ${new_value} | sudo tee ${filename}
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

function configure {
	case ${osfamily} in 
	"RedHat")
		# Redhat based
		if [ "$(whoami)" == "root" ]; then
	                yum install sudo || exit_on_fail
		fi

		# Might want to add make and gcc
		sudo yum install git puppet rubygems ruby-devel || exit_on_fail

		# Only set puppet server and configure the agent if the server is specified
		if [ "${puppet_server}" != "" ]; then
			safe_find_replace -n "/etc/sysconfig/puppet" -p "^#*PUPPET_SERVER=.*$" -v "PUPPET_SERVER=${puppet_server}" -a || exit_on_fail
			sudo puppet resource service puppet ensure=running enable=true || exit_on_fail
		fi

		# If the provided puppet server name matches the local hostname we install the server on this machine
		if [ "${puppet_server}" == "`hostname`" ] || [ "${puppet_server}" == 'localhost' ]; then
			sudo yum install puppet-server || exit_on_fail
			sudo service puppetmaster start || exit_on_fail
			sudo chkconfig puppetmaster on || exit_on_fail
			sudo puppet resource service iptables ensure=stopped || exit_on_fail
			sudo puppet resource service iptables ensure=running enable=true || exit_on_fail
		fi
	;;
	"Debian")
		# Debian based
		if [ "$(whoami)" == "root" ]; then
			apt-get install sudo || exit_on_fail
		fi

		sudo apt-get install git puppet rubygems ruby-dev || exit_on_fail

		# Only set puppet server and configure the agent if the server is specified
		if [ ${puppet_server} != "" ]; then
			safe_find_replace -n "/etc/default/puppet" -p "^#*START=.*$" -v "START=yes" -a || exit_on_fail
			configure_puppet_conf '/etc/puppet/puppet.conf'
		fi

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

	# Only get the git Puppetfile Librarian repo and install r10k if the repo is provided
	# Can't use git clone since the puppet conf dirctory already exists
	# Ignore annoying warning in recent rdoc
	if [ "${puppet_repo}" != "" ]; then
		# Install r10k (librarian replacmeent
		echo "Installing r10k and performing generic configuration steps"
		#sudo gem update --system || exit_on_fail | grep -v "${ignore_warning}"
		sudo gem install r10k || exit_on_fail

		# Pull Librarian config from git repo
		sudo git init "${puppet_conf_dir}" || exit_on_fail
		cd "${puppet_conf_dir}" && sudo git remote add origin "${puppet_repo}" || exit_on_fail
		cd "${puppet_conf_dir}" && sudo git fetch origin || exit_on_fail
		cd "${puppet_conf_dir}" && sudo git checkout -b master --track origin/master || exit_on_fail
		cd "${puppet_conf_dir}" && sudo r10k puppetfile install || exit_on_fail

		if [ "${puppet_server}" == "" ]; then
			# Run Puppet without puppetmaster server
			echo "Running Puppet apply"
			sudo puppet apply -v --modulepath=/etc/puppet/modules -e "include profile::base"
		fi 
	fi

	# If there is a puppet server configured we sign the cert just in case it's not done automatically and restart the agent,else we run puppet apply
	if [ "${puppet_server}" != "" ]; then
		sudo puppet cert sign "`hostname`"
		sudo puppet resource service puppet ensure=stopped || exit_on_fail
		sudo puppet resource service puppet ensure=running enable=true || exit_on_fail
	fi

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

# Configures the puppet.conf file and restarts puppet, takes one parameter, the config file path
function configure_puppet_conf {
	safe_find_replace -n $1 -p '    # The Puppetmaster this client should connect to' -a agent || exit_on_fail
	safe_find_replace -n $1 -p "    server = ${puppet_server}" -a agent || exit_on_fail
	safe_find_replace -n $1 -p '    report = true' -a agent || exit_on_fail
	safe_find_replace -n $1 -p '    pluginsync = true' -a agent || exit_on_fail

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
