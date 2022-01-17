#! /bin/bash

# ****************************************************************************
# N-Agent setup script for Ubuntu Linux platform
#
# This script installs and verifies the agent and n-central settings.
# In case where argument is supplied, The activation key take the
#	highest precedence.
#
# Copyright © 2021 N-able Solutions ULC and N-able Technologies Ltd. All rights reserved.
#
# No part of this software code and/or binary may be reproduced or transmitted
# via any means be they mechnical, electronic or otherwise.  This software may
# not be used under any circumstances without prior written permission by the
# author(s) and copyright holder(s).
#
# THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
# ******************************************************************/         



DEBUG=0

# control variables
INTERACTIVE=0
BLOCKING=0
ERROR_MSG=""
SECRET_VALUE="*****"
# log file
LOG_DIR=/var/log/n-central
if [ ! -d "$LOG_DIR" ]; then
    mkdir $LOG_DIR
fi
LOG_FILE=$LOG_DIR/install_nagent.log

# N-Agent home directory
# must figure out the directories structure fro 32/64 bits sys
HOME=/home/nagent
if [ ! -d "$HOME" ]; then
    mkdir "$HOME"
fi

HOMELIB=$HOME
if [ -f /etc/POS_ver ] || [ -f /etc/N-CHAOS_ver ] || [ -f /etc/THINK_ver ]; then
 	HOME=/etc
  	HOMELIB=/usr/lib/nagent
fi

CONFIG_FILE=$HOME/nagent.conf
if [ $DEBUG -eq 1 ]; then
    LOG_FILE=./install_nagent.log
	CONFIG_FILE=./nagent.conf
fi

 

 

# UTILITIES ----------------------------------------------------------------------------

# log message to file and print to std output if required.
# supports logging of secrets - if they are to stdout (interactive mode), they are printed out, if they are logged into file, secrets are replaced with *****
#                             - usage: log_message "This is my secret: SECRET_VALUE" "mysecret"
log_message()
{
if [[ $1 == *"SECRET_VALUE"* ]]; then
	if [ ! -z "$2" ] ; then
		MESSAGE_STDOUT=$1
		MESSAGE_LOG=$1
		for secret in "${@: 2}"
  		do
                    MESSAGE_STDOUT="${MESSAGE_STDOUT/SECRET_VALUE/$secret}"
		done
		echo -e `date '+%D %T'`"\t${MESSAGE_LOG//SECRET_VALUE/*****}" >> $LOG_FILE
		echo -e "$MESSAGE_STDOUT"
	fi
else
	MESSAGE=$*
	echo -e `date '+%D %T'`"\t$MESSAGE" >> $LOG_FILE
	echo -e "$MESSAGE"
fi
}

log_install()
{
	MESSAGE=$*
	echo -e `date '+%D %T'`"\t$MESSAGE" >> $LOG_FILE
}


SYS_IP=""       #ip addr of this box
SYS_MAC=""      #MACC addr of this box
HOST_NAME=""    #hostname of this box
SYS_TYPE=""      #64/32 bits system
DISTRIBUTION=""
VERSION=""
# parse InstallationData.xml file if any
parse_xml_node()
{
	startline=$(grep -n "<$1>"  InstallationData.xml | cut -d':' -f1)
	lastline=$(grep -n "<\/$1>"  InstallationData.xml | cut -d':' -f1)
	value=$(sed -n $startline,$lastline'p' InstallationData.xml)
	value=$(echo $value | sed -e "s/^.*<$2/<$2/" | sed -e "s/<$2>//g" | sed -e "s/<\/$2>//g" | awk -F"<" '{print $1}' | sed -e 's/[[:space:]]*$//' )
}
check_installationdata()
{
	installationdata=0
	if [ -f InstallationData.xml ]; then
		parse_xml_node Customer ID
		CID=$value
		parse_xml_node Customer Name
		CNAME=$value
		parse_xml_node Server URL
		SERVER=$value
		parse_xml_node Server Protocol
		PROTOCOL=$value
		parse_xml_node Server Port
		PORT=$value
		parse_xml_node Proxy URL
		proxyurl=$value
		if [ -n "$proxyurl" ]; then
			parse_xml_node Proxy Port
			proxyport=$value
		fi
		if [ -n "$proxyurl" ] &&  [ -n "$proxyport" ]; then
			PROXY="$proxyurl:$proxyport"
		fi
		parse_xml_node InstallationData RegistrationToken
		REGISTRATION_TOKEN=$value
		echo "Customer ID: $CID"
		echo "GUID: $CNAME"
		echo "Server IP: $SERVER"
		echo "Protocol: $PROTOCOL"
		echo "Port: $PORT"
		echo "Proxy: $PROXY"
		echo "RegistrationToken: $REGISTRATION_TOKEN"
		echo "InstallationData.xml was found. Do you want to continue installation with data (y/n)?"
		installationdata=1
	fi
}
# Determine the Linux distribution and version that is being run.
get_OS_name()
{
    # Check for GNU/Linux distributions
    if [ -f /etc/SuSE-release ]; then
        DISTRIBUTION="suse"
    elif [ -f /etc/UnitedLinux-release ]; then
        DISTRIBUTION="united"
    elif [ -f /etc/debian_version ]; then
        DISTRIBUTION="debian"
    elif [ -f /etc/redhat-release ]; then
        a=`grep -i 'red.*hat.*enterprise.*linux' /etc/redhat-release`
        if test $? = 0; then
            DISTRIBUTION=rhel
        else
            a=`grep -i 'red.*hat.*linux' /etc/redhat-release`
            if test $? = 0; then
                DISTRIBUTION=rh
            else
                a=`grep -i 'cern.*e.*linux' /etc/redhat-release`
                if test $? = 0; then
                    DISTRIBUTION=cel
                else
                    a=`grep -i 'scientific linux cern' /etc/redhat-release`
                    if test $? = 0; then
                        DISTRIBUTION=slc
					else
                        a=`grep -i 'CentOS' /etc/redhat-release`
						if test $? = 0; then
                			DISTRIBUTION=CentOS
                    	else
                            a=`grep -i 'Fedora' /etc/redhat-release`
    						if test $? = 0; then
                    			DISTRIBUTION='Fedora'
                    		else
					a='grep -i ubuntu /etc/lsb-release'
					if test $? = 0; then
						DISTRIBUTION='ubuntu'
					else
						DISTRIBUTION="unknown"
					fi
                        	fi
                    	fi
					fi
                fi
            fi
        fi
    else
        DISTRIBUTION="unknown"
    fi

    ###    VERSION=`rpm -q redhat-release | sed -e 's#redhat[-]release[-]##'`
    case ${DISTRIBUTION} in
        rh|cel|rhel)
            VERSION=`cat /etc/redhat-release | sed -e 's#[^0-9]##g' -e 's#7[0-2]#73#'`
            ;;
        slc)
            VERSION=`cat /etc/redhat-release | sed -e 's#[^0-9]##g' | cut -c1`
            ;;
        debian)
            VERSION=`cat /etc/debian_version`
            if [ ${VERSION} = "testing/unstable" ]; then
                # The debian testing/unstable version must be translated into
                # a numeric version number, but no number makes sense so just
                # remove the version all together.
                VERSION="" #""
            fi
            ;;
        suse)
            VERSION=`cat /etc/SuSE-release | grep 'VERSION' | awk '{ print $3}'`
            ;;
        united)
            VERSION=`cat /etc/UnitedLinux-release`
            ;;
		CentOS)
			VERSION=`cat /etc/redhat-release | awk '{ print $3}'`
			;;
	ubuntu)
		VERSION=`grep -i DISTRIB_RELEASE /etc/lsb-release | sed -e 's#[^0-9.]##g'`
		;;

        *)
            VERSION='00'
            ;;
    esac;
}


# get this box's IP
get_ip()
{
	OS=`uname`
	case $OS in
   		Linux) tempo=`ifconfig  | grep 'inet addr:\|inet '| grep -v '127.0.0.1' | cut -d\t -f2 | cut -d' ' -f2 | cut -d: -f2 | awk '{ print $1}'`
		#SYS_IP=$(arp $(hostname) | awk -F'[()]' '{print $2}')
		;;
   		
		FreeBSD|OpenBSD) tempo=`ifconfig  | grep -E 'inet.[0-9]' | grep -v '127.0.0.1' | awk '{ print $2}'` 
		;;
   		
		SunOS) tempo=`ifconfig -a | grep inet | grep -v '127.0.0.1' | awk '{ print $2} '` 
		;;
   		
		*) tempo="Unknown";;
	esac

	for ipa in $tempo; do
		if [ -z "$SYS_IP" ]; then
			SYS_IP=$ipa
		else
			SYS_IP="$SYS_IP, $ipa"
		fi
	done
}

# get this box MAC address
get_MAC()
{	
	OS=`uname`
	case $OS in
    	Linux) SYS_MAC=`ifconfig  | grep 'Link encap:Ethernet'| grep -v '00:00:00:00:00:00' | awk -F 'HWaddr ' '{ print $2 }'`
	if [ -z "$SYS_MAC" ]; then
		SYS_MAC=`ifconfig | grep ether | grep -v '00:00:00:00:00:00' | awk '{ print $2 }'`
	fi
		#`ifconfig | grep -m 1 HWaddr | awk -F 'HWaddr ' '{ print $2 }'`
		;;
   		
		*) SYS_MAC="Unknown";;
	esac 
}

# 32 or 64 bit system
get_busType()
{
    # need to parse this string for the right bus type ???
    # i686 x86_64 AMD64 EM64T
    mySys=`uname -m | grep _64`;
    if [ -z $mySys ]; then 
        SYS_TYPE=32
    else
        SYS_TYPE=64
    fi
}

# get a minimum set of information fro this box
asset_disco()
{
    get_ip
    HOST_NAME=`hostname`
    if [ -z $HOST_NAME ]; then
        HOST_NAME=$SYS_IP
    fi
    get_MAC
    get_busType
    get_OS_name

    #memory
    MEMORY=`free | grep Mem | awk '{print $2}'`
    
    #cpu info
    CPUS=`cat /proc/cpuinfo | grep processor | wc -l | awk '{print $1}'`
    CPU_MHZ=`cat /proc/cpuinfo | grep MHz | tail -n1 | awk '{print $4}'`
    CPU_TYPE=`cat /proc/cpuinfo | grep vendor_id | tail -n 1 | awk '{print $3}'`
    
    #BOOT=`procinfo | grep Bootup | sed 's/Bootup: //g' | cut -f1-6 -d' '`
    #UPTIME=`uptime | cut -f5-8 -d' '`
    
    echo
    log_message "Current system information: "
    log_message "\tName:\t\t$HOST_NAME"
    log_message "\tIP address:\t$SYS_IP"
    log_message "\tMAC address:\t$SYS_MAC"
	log_message "\tCPU Info:\t$SYS_TYPE BIT-$CPUS CPU $CPU_MHZ MHZ $CPU_TYPE"
    log_message "\tDistribution:\t$DISTRIBUTION $VERSION"
}


# bash has problem with variable scope. Use this method only
# when no need to update the global variables
spinner()
{

    SP_STRING=${2:-"'|/=\'"}
    while [ -d /proc/$1 ]
    do
        printf "$SP_COLOUR\e7  %${SP_WIDTH}s  \e8\e[0m" "$SP_STRING"
        sleep ${SP_DELAY:-0.1}
        SP_STRING=${SP_STRING#"${SP_STRING%?}"}${SP_STRING%?}
    done
    
} 


wait()
{
    sleep $1
}

#wait 3 &
#spinner "$!" '.o0O'

# END UTILITIES ------------------------------------------------------------------------



# must install as root/sudo
if [ $DEBUG -eq 1 ]; then
	log_install "Run in debug mode ..."
else
	if [ `id -ur` -ne 0 ]; then
        echo "Insufficient permissions. Run as root"
        exit;
	fi;
fi


# do not allow abort while installing.
handle_abort()
{
    if [ $BLOCKING == 1 ]; then
	    log_install "BLOCKED: User was trying to abort while installation is running ..."
	else
	    log_message "User aborted installation ..."
	    
	    # cleanup
	    
	    exit 0
	fi
}
trap handle_abort SIGHUP SIGINT SIGTERM

# FORWARD DECLARATION - go to the bottom of the script for main loop --------------




# here are the menu section
MENU_LEVEL=1	#wizard - where we are
ACTIVATE_KEY=""	#activation key
SERVER=""		#n-central IP
CNAME=""		#customer name
CID=""			#customer ID
PROTOCOL=""		#http/https
PORT=""			#443/80/8080
PROXY=""		#server proxy
APPLIANCE=""	#appliance ID
REGISTRATION_TOKEN=""  #Registration token

# clear previous parameters
reset_data()
{
	MENU_LEVEL=1
	ACTIVATE_KEY=""
	SERVER=""
	CNAME=""
	CID=""
	PROTOCOL=""
	PORT=""
	PROXY="" 
	REGISTRATION_TOKEN=""
}

#""
print_usage()
{
	echo "Usage: ./install.sh -k activation-key [-x proxy]
	OR ./install.sh -c customer-name -i customer-id -s server-IP -p protocol -a port -t registration-token [-x proxy]
	
	To uninstall, run ./install.sh -u
	To repair configuration file, run ./install.sh -r activation-key"
}

print_goto_menu()
{
	echo "m.) Go back to main menu"
}

print_Hint()
{
	echo "3.) quit"
	echo "NOTE: To install agent in silent mode, select '3' to quit and run:
	./install.sh -h for available options."
}

print_prompt()
{
    echo
    echo -en "Please pick an option: "
}

print_menu()
{

    echo "Ubuntu Linux agent configuration menu."
	echo "1.) Install"
    echo "2.) Uninstall"
	print_Hint
	MENU_LEVEL=1

	print_prompt
}

# installing with activation key?
print_select1()
{
	echo "1.) Install using activation key
	(Note: key is obtained from N-Central UI)"
	echo "2.) User-Interactive Installation"
	print_Hint
	MENU_LEVEL=2

	print_prompt
}

get_activateKey()
{
	echo "Please enter activation key:"
	read ACTIVATE_KEY
	MENU_LEVEL=1
}

# install with customer's info
print_select2()
{
	echo "1.) Customer name"
    echo "2.) Customer ID"
	print_Hint
	MENU_LEVEL=3

	print_prompt
}


get_customer_name()
{
	echo -en "Please enter customer name or site name: "
	read CNAME
	MENU_LEVEL=1
}


get_customer_ID()
{
	echo -en "Please enter customer ID: "
	read CID
	MENU_LEVEL=1
}

get_registration_token()
{
	echo "Please enter registration token for this customer:"
	read REGISTRATION_TOKEN
	MENU_LEVEL=1
}

# get server's settings
get_server_prms()
{
	echo "Please enter N-Central server address (e.g.: 192.168.1.2 or google.com):"
	read SERVER
	echo -en "Please enter the communication port (e.g.: 80): "
	read PORT
	echo -en "Please enter the communication protocol (e.g.: http): "
	read PROTOCOL
	echo -en "Please enter server proxy (optional, press enter to skip): "
	read PROXY
	MENU_LEVEL=1
}

# get the same set of server's settings for backup server
get_backup_server()
{
	echo -en "Would you like to configure a N-Central backup server (y/n)? "
	read doAdd
	if [ "$doAdd" == "y" -o "$doAdd" == "Y" ]; then
		echo "Please enter N-Central server address (e.g.: 192.168.1.2 or google.com):"
		read SERVER[1]
		echo -en "Please enter the communication port (e.g.: 80): "
		read PORT[1]
		echo -en "Please enter the communication protocol (e.g.: http): "
		read PROTOCOL[1]
		echo -en "Please enter server proxy (optional, press enter to skip): "
		read PROXY[1]
		MENU_LEVEL=1
	fi
}

# reviewing installation's parameters
print_settings()
{
    asset_disco
    if [ $? -ne 0 ]; then
        log_install "ERROR: unable to collect system information."
    fi
    echo

    log_message "Setup is run with the following settings:"
    server_address=$SERVER
    if [ -z $ACTIVATE_KEY ] ; then
        log_message "	Customer name: 			$CNAME"
        log_message "	Customer ID: 			$CID"
        log_message "	Registration token:		SECRET_VALUE" "$REGISTRATION_TOKEN"
        if [ -f $CONFIG_FILE ]; then
            server_address=$(grep server= $CONFIG_FILE | tr "=", " " | awk '{ print $2}')
        fi
    else
        log_message "	Activation key:			SECRET_VALUE" "$ACTIVATE_KEY"
    fi
    log_message "	N-Central server address:	$server_address"
    log_message "	Communication protocol:		$PROTOCOL"
    log_message "	Communication port:		$PORT"
    if [ "$PROXY" != "" ]; then
        log_message "	Server's proxy:			$PROXY"
    fi
}
# end of menu section




# AGENT INSTALLATION -------------------------------------------------------------------
#""

# appliance must be an integer
ValidateAppID()
{
  ANS=$(echo $1 | grep '^[0-9]*$')
  if [ -z $ANS ]; then
    return 1
  else
    if [ $ANS -gt 0 ]; then
      return 0
    else
      return 1
    fi
  fi
}

# agent is appliance type 1
ValidateAppType()
{
  case $1 in
    1) return 0;;
    *) return 1;;
  esac
}

ValidateRegistrationToken(){
  if [ --n $1 ]; then
      return 0
    else
      return 1
  fi
}


GetProtocolFromKey()
{
  RET=${1%%://*}
  if [ $RET == $1 ]; then
    #no protocol defined, use default 'http'
    RET="http"
  else
    if [ -n $RET ]; then
      RET=$( echo $RET | tr '[:upper:]' '[:lower:]')
    else 
      RET="http"
    fi
  fi
  echo $RET
}

# protocol is either http or https
ValidateProtocol()
{
#  if [ $1 == 'http' ] || [ $1 == 'https' ]; then
 #   CheckOpen=$( rpm -qa | grep -i openssl | head -1 )
#	if [ -z $CheckOpen -o ! -f "/usr/bin/openssl" ]; then
#        return 2
#    fi
    return 0
#  else
#    return 1
#  fi
}

GetHostNameFromKey()
{
  #remove the possible protocol part
  RET=${1#*://}
  #remove the possible port part
  RET=${RET%:*}
  echo $RET
}

# host is either an IP address or a hostname
ValidateHost()
{
  ANS=$( echo $1 | grep '[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*' )
  if [ -z $ANS ]; then
    #hostname
    ANS=$( host $1 | grep -i "not found" )
    if [ -z "$ANS" ]; then
      return 0
    else
      return 1
    fi
  else
    #ip address
    TMPIFS=$IFS
    IFS=.
    #make sure the ip address does not exceeds 3 digits
    for net in $ANS
    do
      if [ ${#net} -gt 3 ]; then
        IFS=$TMPIFS
        return 1
      fi
    done
    IFS=$TMPIFS
    return 0
  fi
}

GetPortFromKey()
{
  #remove the possible protocol part
  TMP=${1#*://}
  #remove the possible host name part
  RET=${TMP#*:}
  if [ $RET == $TMP ]; then
    #no port
    echo
  else
    echo $RET
  fi
}

# port is an integer
ValidatePort()
{
  ANS=$(echo $1 | grep '^[0-9]*$')
  if [ -z "$ANS" ]; then
    return 1
  else
    if [ 0 -lt $ANS ] && [ $ANS -lt 65536 ]; then
      return 0
    else
      return 1
    fi
  fi
}

# customer ID is an integer
ValidateCustomerID()
{
  ANS=$(echo $1 | grep '^[0-9]*$')
  if [ -z "$ANS" ]; then
    return 1
  else
    if [ 0 -lt $ANS ]; then
      return 0
    else
      return 1
    fi
  fi
}


# Remove all agent's packages
uninstall()
{
	log_install "Uninstalling ... "
	BLOCKING=1
    echo ""

    # Step 1: Stop agent service
    if [ -f /bin/systemctl ]; then
        echo "Stop agent and delete systemd items"
        systemctl stop nagent
        rm -f /lib/systemd/system/nagent.service
        systemctl daemon-reload
    else
        echo "Stop n-agent"
		update-rc.d -f nagent remove
		service nagent stop
    fi


#      rm /opt/nable/usr/lib/libodbc.so.1

    # Step 2: Remove agent and its libraries

    dpkg -r nagent
    if [ $? -ne 0 ]; then
        echo "Fail to remove nagent"
    else
        echo "nagent removed"
    fi

    # Step 3: Cleanup left over folders
    rm -rf /var/log/n-central
    rm -f /opt/nable/usr/lib/lib*.so
    # Step 2: Cleanup crontab
    sed '/ root logrotate \/etc\/logrotate.d\/nagent/d' /etc/crontab > /tmp/crontab
    sed '/ root run-parts \/etc\/cron.fivem/d' /tmp/crontab > /tmp/crontab1
    cp -f /tmp/crontab1 /etc/crontab
    rm -f /tmp/crontab*
#	rm -rf /tmp/MMS
	if [ $INTERACTIVE -eq 0 ]; then
		log_message "Uninstall completed"
	else
    	logmessage "Uninstall completed. Press enter to continue"
    	read LINE
	fi
	
}

# decrypt activation key and save its enclosed data
process_activation()
{
	log_install "Decrypting key ..."
	echo -en "\nAnalysing activation key. Please wait ..."
	
	# Check if openssl is installed
#	CheckOpen=$( rpm -qa | grep -i openssl | head -1 )
#	if [ -z $CheckOpen -o ! -f "/usr/bin/openssl" ]; then
#  		echo -en "Openssl is not installed, not able to decode the base64 encrypted activation key.\n"
#		IFS=$OLDIFS

#  		return 1
#	else
#		log_install "Openssl is available."
#	fi

    # Decode the key
	KEY=$ACTIVATE_KEY
	DecodedKey=$(echo $KEY | openssl enc -base64 -d)
	# If cannot decrypt repeat with option -A for base64 line with more than 76b characters
	if [ -z $DecodedKey ]; then
		DecodedKey=$(echo $KEY | openssl enc -base64 -d -A)
	fi
	# Check the decrypted key
	if [ -z $DecodedKey ]; then
  		log_message "ERROR: Can not decrypt the activation key ($ACTIVATE_KEY)"
		IFS=$OLDIFS

  		return 2
	#else
		#log_install "The decrypted key is $DecodedKey"
	fi

	EndPoints=$( echo -n $DecodedKey | cut -d\| -f1 )
	APPLIANCE=$( echo -n $DecodedKey | cut -d\| -f2 )
	ApplianceType=$( echo -n $DecodedKey | cut -d\| -f3 )
	REGISTRATION_TOKEN=$( echo -n $DecodedKey | cut -d\| -f4 )
	log_install "EndPoints are $EndPoints"
	log_install "ApplianceID is $APPLIANCE"
	log_install "ApplianceType is $ApplianceType"


	# Validate AppID
	ValidateAppID $APPLIANCE
	if [ $? -ne 0 ]; then
  		log_message "ERROR: Invalid ApplianceID=$APPLIANCE"

  		return 3
	else
		log_install "Valid ApplianceID=$APPLIANCE"
	fi

	# Validate AppType
	ValidateAppType $ApplianceType
	if [ $? -ne 0 ]; then
        log_message "ERROR: Invalid ApplianceType=$ApplianceType"
  		return 4
	else
		log_install "Valid ApplianceType=$ApplianceType"
	fi

	# parse endpoint for data
    # Set the field seperator to ','
	OLDIFS=$IFS
	IFS=,
	
	counter=0
	for endpoint in $EndPoints
	do
		#save upto 2 endpoints
  		if [ $counter -ge 2 ]; then
    		break
  		fi

		#get protocol
  		Protocol=$(GetProtocolFromKey $endpoint)
  		ValidateProtocol $Protocol
        RET=$?
  		if [ $RET -ne 0 ]; then
            if [ $RET -eq 2 ]; then
                log_message "ERROR: OpenSSL not installed"
            else
                log_message "ERROR: Invalid Protocol[$counter]=$Protocol"
            fi
			IFS=$OLDIFS

    		return 5
		else
			log_install "Valid Protocol[$counter]=$Protocol"
  		fi

		#get and validate hostname
  		HostName=$(GetHostNameFromKey $endpoint)
  		ValidateHost $HostName
  		if [ $? -ne 0 ]; then
    		log_message "ERROR: Invalid Host[$counter]=$HostName"
			IFS=$OLDIFS

    		return 6
		else
			log_install "Valid Host[$counter]=$HostName"
  		fi

		#get and validate port
  		Port=$(GetPortFromKey $endpoint)
  		if [ -z $Port ]; then
    		#set the default port, 80 for http and 443 for https
    		if [ $Protocol == "http" ]; then 
      			Port=80
    		else
      			Port=443
    		fi
  		fi
  		ValidatePort $Port
  		if [ $? -ne 0 ]; then
    		log_message "ERROR: Invalid Port[$counter]=$Port"
			IFS=$OLDIFS

    		return 7
		else
			log_install "Valid Port[$counter]=$Port"
  		fi

  		if [ $counter -eq 0 ]; then
			PROTOCOL=$Protocol
			SERVER=$HostName
			PORT=$Port
  		else
  		    PROTOCOL[1]=$Protocol
			SERVER[1]=$HostName
			PORT[1]=$Port
		fi

  		((counter=$counter + 1))
	done

	IFS=$OLDIFS
	log_install "Dycrypting key finished."
}


# run a method in background
# all allputs are written to error file
# the process_bg_msg will read the first ERROR and delete the error file
BG_ERROR_FILE=/tmp/install_errors.$$
process_bg_msg()
{
    retMsg=$(cat $BG_ERROR_FILE | grep -i 'error')
    rm -f $BG_ERROR_FILE
    
    if [ ! -z "$retMsg" ]; then
        echo -e "$retMsg\n"
        return 1
    else
        return 0
    fi
}

# write configuration parameters to file
# set $1 to init to skip the server section.
update_conf()
{
	writeAll=$1
	log_install "Update config file ... $writeAll"
	
    mkdir -p "$HOME"
    
	if [ -f $CONFIG_FILE ]; then
		mv $CONFIG_FILE "$CONFIG_FILE.back"
	fi
	
	# Create the MAIN section of the configuration file
	echo -e "[main]" >> $CONFIG_FILE
	echo -e "\tlogfilename=$LOG_DIR/nagent.log" >> $CONFIG_FILE
	echo -e "\tloglevel=1" >> $CONFIG_FILE
	echo -e "\thomedir=$HOMELIB" >> $CONFIG_FILE
	echo -e "\tthread_limitation=50" >> $CONFIG_FILE
	echo -e "\tpoll_delay=1" >> $CONFIG_FILE
	echo -e "\tdatablock_size=20" >> $CONFIG_FILE
	echo -e "\tos_version=16_64" >> $CONFIG_FILE

	if [ "$writeAll" != "init" ]; then
		# SOAP section
		echo "[soap]" >> $CONFIG_FILE 
	
		#write valid end points to conf file
		counter=0
		for endpoint in $SERVER
		do
			if [ $counter -eq 0 ]; then
	    		echo -en "\tprotocol=$PROTOCOL\n" >> $CONFIG_FILE
	    		echo -en "\tserver=$SERVER\n" >> $CONFIG_FILE
	    		echo -en "\tport=$PORT\n" >> $CONFIG_FILE
	    		echo -en "\tproxy=$PROXY\n\n" >> $CONFIG_FILE
	  		else
	    		echo -en "\tprotocol_$counter=$PROTOCOL[1]\n">> $CONFIG_FILE
	    		echo -en "\tserver_$counter=$SERVER[1]\n" >> $CONFIG_FILE
	    		echo -en "\tport_$counter=$PORT[1]\n" >> $CONFIG_FILE
	    		echo -en "\tproxy_$counter=$PROXY[1]\n\n" >> $CONFIG_FILE
	  		fi
	
	  		((counter=$counter + 1))
		done
	
		echo -en "\tendpoint_size=$counter\n" >> $CONFIG_FILE
		echo -en "\tapplianceid=$APPLIANCE\n" >> $CONFIG_FILE
		echo -en "\tServer_ro=no\n" >> $CONFIG_FILE
	fi
}

# build paramters string and send it to network-checker
# if net work checker return error, send it back to the caller.
# Expecting:
#   $1: the data type 0-customername, 1-customerID, 2-applianceID
#   $2: customer's name/ID or applicanceId
DMS_ValidData()
{
    log_install "DMS validating data ..."
    if [ ! -f "InitialValidate" ]; then
        log_install "DMS checker does not exist"
        return 99
    fi

    optString="-f $CONFIG_FILE -l $LOG_FILE"
    if [ $1 -eq 0 ]; then
        optString="$optString -c \"$CNAME\" -t $SECRET_VALUE"
    elif [ $1 -eq 1 ]; then
        optString="$optString -i $CID -c \"$CNAME\" -t $SECRET_VALUE"
    elif [ $1 -eq 2 ]; then
        optString="$optString -a $APPLIANCE -t $SECRET_VALUE"
    else
        log_message "ERROR: DMS cannot validate $2 of type $1"
    fi

    if [ ! -z "$PROXY" ]; then
	optString="$optString -x $PROXY"
    fi
	
	# Make sure openssl is installed
#	log_message "Checking openssl version 098e"    
#	SSL_LIB="openssl098e-0.9.8e-18.el6_5.2.x86_64.rpm"
#    if `rpm -q --queryformat '%{VERSION}-%{ARCH}\n' openssl openssl098e | grep "0.9.8e-x86_64" 1>/dev/null 2>&1` ; then
#    	log_message "openssl version 098e is already installed"
#    else
#    	log_message "openssl version 098e is not available. Attempting to #install $SSL_LIB"
#        # Install package for 64-bit system
#        if rpm -Uvh $SSL_LIB ; then
#	    	log_message "openssl version 098e installation was successful"
#        else
#            log_message "Failed to install $SSL_LIB. The installation will #exit."
#			log_message "Please install $SSL_LIB manually and try # install again."
#           	exit 1
#        fi		
#	fi
	export LD_LIBRARY_PATH=./:$LD_LIBRARY_PATH 
    log_install "./InitialValidate -s $SERVER -n $PORT -p $PROTOCOL $optString"
    #retString=$(./InitialValidate -s $SERVER -n $PORT -p $PROTOCOL $optString)
    echo "Wait for server(s) response ..."
    if [ $1 -eq 0 ]; then
	if [ ! -z "$PROXY" ]; then
	    retString=$(./InitialValidate -s $SERVER -n $PORT -p $PROTOCOL -f $CONFIG_FILE -l $LOG_FILE -c "$CNAME" -i $CID -t $REGISTRATION_TOKEN -x $PROXY)
	else
	    retString=$(./InitialValidate -s $SERVER -n $PORT -p $PROTOCOL -f $CONFIG_FILE -l $LOG_FILE -c "$CNAME" -i $CID -t $REGISTRATION_TOKEN)
	fi
    elif [ $1 -eq 1 ]; then
	if [ ! -z "$PROXY" ]; then
	    retString=$(./InitialValidate -s $SERVER -n $PORT -p $PROTOCOL -f $CONFIG_FILE -l $LOG_FILE -i $CID -c "$CNAME" -t $REGISTRATION_TOKEN -x $PROXY)
	else
	    retString=$(./InitialValidate -s $SERVER -n $PORT -p $PROTOCOL -f $CONFIG_FILE -l $LOG_FILE -i $CID -c "$CNAME" -t $REGISTRATION_TOKEN)
	fi
    elif [ $1 -eq 2 ]; then
	if [ ! -z "$PROXY" ]; then
	    retString=$(./InitialValidate -s $SERVER -n $PORT -p $PROTOCOL -f $CONFIG_FILE -l $LOG_FILE -a $APPLIANCE -t $REGISTRATION_TOKEN -x $PROXY)
	else
	    retString=$(./InitialValidate -s $SERVER -n $PORT -p $PROTOCOL -f $CONFIG_FILE -l $LOG_FILE -a $APPLIANCE -t $REGISTRATION_TOKEN)
	fi
    fi
    retCode=$?
    if [ $retCode -ne 0 ]; then 
		case $retCode in
			1) ERROR_MSG="ERROR: Missing server information: $SERVER:$PORT, $PROTOCOL"
				;;
			2) ERROR_MSG="ERROR: Duplicate server information: $SERVER:$PORT, $PROTOCOL"
				;;
			3) ERROR_MSG="ERROR: Missing configuration file location: $optString"
				;;
			4) ERROR_MSG="ERROR: Duplicate configuration file $CONFIG_FILE";
				;;
			5) ERROR_MSG="ERROR: Missing identification: name($CNAME), ID($CID), appliance($APPLIANCE)"
				;;
			6) ERROR_MSG="ERROR: InitialValidate with more than one identity type"
				;;
			7) ERROR_MSG="ERROR: Missing install log file location"
				;;
			8) ERROR_MSG="ERROR: Duplicate log file location"
				;;
			9) ERROR_MSG="ERROR: Unrecognized options in input"
				;;
			10) ERROR_MSG="ERROR: Cannot connect to n-central server $PROTOCOL://$SERVER:$PORT"
				;;
			11) ERROR_MSG="ERROR: Invalid customer name $CNAME"
				;;
			12) ERROR_MSG="ERROR: Invalid customer ID $CID"
				;;
			13) ERROR_MGS="ERROR: Invalid appliance ID $APPLIANCE"
				;;
			14) ERROR_MSG="ERROR: Unable to scan local system's assets"
				;;
			15) ERROR_MSG="ERROR: Unable to register this appliance $APPLIANCE with server $SERVER:$PORT, $PROTOCOL.\nContact system administrator for more information."
				;;
			16) ERROR_MSG="ERROR: Unable to access configuration file $CONFIG_FILE"
				;;
			17) ERROR_MSG="ERROR: Unable to access log file"
				;;
			*) ERROR_MSG="ERROR: InitialValidate failed! Exit status code: $retCode"
				;;
#			log_message $ERROR_MSG
		esac

        return $retCode
	else
		if [ $DEBUG -eq 1 ]; then
			echo -e "InitialValidate returns ==> $retString ==> $retCode\n"
			#APPLIANCE=$retCode
			#update_conf
		fi

		# everything is fine, config file should be available now.
		# get application ID from config file to be sure
		tmpID=$(grep "applianceid=" $CONFIG_FILE | cut -d= -f2 | awk '{ print $1}')
		if [ -z "$tmpID" ]; then
			log_message "ERROR: Invalid appliance ID received!"
		fi
		log_install " ID from file: $tmpID"
    fi
    
    return 0
}



# extract and copy packages to home directory
# Requires the unixODBC and RPM all agent's packages.
do_install() 	
{
    BLOCKING=1

    log_message "installing ..."

         # clean up
#       rm -rf *devel*
#       rm -rf /tmp/MMS
#
        # copy files
#       log_install "Copying libodbc.so"
#       cp libodbc.so.1 /opt/nable/usr/lib

    log_install "Installing nagent..."
    dpkg -i nagent.deb
    retCode=$?
    if [ $retCode -ne 0 ]; then
        log_message "ERROR: Failed to install nagent ($retCode)"
        exit $retCode
    fi

    cp uninstall.sh $HOME/uninstall.sh
    cp nagent_download.sh $HOME

    return 0
}


# aHR0cHM6Ly9ob3N0LTgwLmxhYi5uLWFibGUuY29tOjQ0M3wzNDA0OHwxfDA=
# check parameters' syntax before install
install()
{
	# create the initial section for configuration file
	update_conf "init"

	# libstdsoap2 is needed for InitialValidate
    #if ! rpm -q libstdsoap2 >/dev/null 2>&1 ; then
    #    if ! rpm -Uvh --nodeps libstdsoap2*.rpm ; then
    #        log_message "ERROR: Cannot install SOAP package for validation."
    #        return 99
    #    else
    #    	ldconfig
    #    fi
    #fi

	# check argument syntax
    # if we do not have activation key, verify that we have all
	# required parameters. 
	if [ -z $ACTIVATE_KEY ]; then
		if [ -z "$SERVER" ]; then
			log_message "ERROR: Missing N-Central server address"

			return 1
		fi

		if [ -z "$PROTOCOL" ]; then
			log_message "ERROR: Missing communication protocol"

			return 1
		fi

		if [ -z "$PORT" ]; then
			log_message "ERROR: Missing communication port"

			return 1
		fi

        counter=0
		for addr in $SERVER
		do
			ValidateProtocol ${PROTOCOL[$counter]}
            RET=$?
			if [ $RET -ne 0 ]; then
				if [ $RET -eq 2 ]; then
                    log_message "ERROR: OpenSSL not installed"
                else
                    log_message "ERROR: Invalid Protocol ${PROTOCOL[$counter]}"
                fi
				return 1
			fi
			servCheck=1
			for OneServer in $(echo ${SERVER[$counter]} | tr "," "\n")
			do
				log_message "Validation of $OneServer Server"
				ValidateHost $OneServer
				if [ $? -ne 0 ]; then
					log_message "ERROR: invalid server $OneServer"
				else
					servCheck=0
					log_message "$OneServer Server looks good"
				fi
			done
			if [ $servCheck -eq 1 ]; then
				return $servCheck
			fi
			ValidatePort ${PORT[$counter]}
			if [ $? -ne 0 ]; then
				log_message "ERROR: invalid port ${PORT[$counter]}"

				return 1
			fi
       
	   		((counter=$counter + 1))
		done

		if [ -z "$CID" ] && [ -z "$CNAME" ]; then
			log_message "ERROR: Missing customer name or ID"

			return 1
		fi

		if [ -z "$REGISTRATION_TOKEN" ]; then
			log_message "ERROR: Missing registration token"

			return 1
		fi
		
		if [ ! -z "$CID" ]; then	 
	        ValidateCustomerID $CID
		    if [ $? -ne 0 ]; then
				log_message "ERROR: invalid customer ID $CID"

				return 1
			fi
			useCustID=1
			custData=$CID
		else
		    useCustID=0
		    custData=$CNAME
		fi
		
    	DMS_ValidData $useCustID $custData
		dmsErr=$?
    	if [ $dmsErr -ne 0 ]; then
    	    log_message $ERROR_MSG
    	    return 1
		else
			log_message "DMS sent applianceID $APPLIANCE"
    	fi
    else
        useCustID=2
	    DMS_ValidData $useCustID $APPLIANCE
		dmsErr=$?
    	if [ $dmsErr -ne 0 ]; then
    	    log_message $ERROR_MSG
    	    return 1
		else
			log_message "DMS sent applianceID $APPLIANCE"
    	fi
	fi


    #  - continue to installation
	clear
	validCont="" #""
	print_settings
	echo
	# confirm on installation
	if [ $INTERACTIVE = 1 ]; then
		echo -en "Continue installation with these settings (y/n)?: "
		read validCont
		if [ "$validCont" == "y" -o "$validCont" == "Y" ]; then
			do_install > $BG_ERROR_FILE 2>&1 &
			spinner "$!" "installing ..."
			process_bg_msg
			if [ $? -ne 0 -o ${PIPESTATUS[0]} -ne 0 ]; then
				return 2
			fi
		else
			log_message "User aborts installation!"
			return 2
		fi
	else
		do_install > $BG_ERROR_FILE 2>&1 &
		spinner "$!" "installing ..."
		process_bg_msg
		if [ $? -ne 0 -o ${PIPESTATUS[0]} -ne 0 ]; then
		    log_install "ERROR: do_install failed"
			return 2
		fi
	fi
	echo  "*/9 * * * * root logrotate /etc/logrotate.d/nagent >/dev/null" >> /etc/crontab
	if [ -f /bin/systemctl ]; then
		echo "Switch to systemd"
		echo -e '[Unit]\nDescription=N-able Agent\nAfter=cron.service network-manager.service\n[Service]\nEnvironment="LD_LIBRARY_PATH=/opt/nable/usr/lib/"\nExecStart=/usr/sbin/nagent -f /home/nagent/nagent.conf\nExecStartPost=/bin/bash -c "echo `pidof -s nagent` > /var/run/nagent.pid"\nExecStop=/bin/bash -c "if [ -f /var/run/nagent.pid ]; then rm -f /var/run/nagent.pid; fi"\nPIDFile=/var/run/nagent.pid\nRestart=always\n\nKillMode=process\n[Install]\nWantedBy=multi-user.target' > /lib/systemd/system/nagent.service
		ln -sf /lib/systemd/system/nagent.service /etc/systemd/system/multi-user.target.wants/nagent.service
		# remove init.d nagent script
		rm -f /etc/init.d/nagent
		# start nagent
		systemctl daemon-reload
		systemctl stop nagent
		echo "enable nagent"
                systemctl enable nagent
		echo "start nagent"
		systemctl --no-block start nagent
	else
		echo "Switch to init.d"
		update-rc.d nagent defaults
		service nagent start
	        echo  "*/5 * * * * root run-parts /etc/cron.fivem" >> /etc/crontab
	fi

	log_message "Installation completed."
	sleep 1
	NAGENTPID=`pidof nagent`
	if [ ! -z $NAGENTPID ]; then
		echo "nagent started. PID=$NAGENTPID"
	fi
	if [ $INTERACTIVE -eq 1 ]; then
		echo "Press enter to continue"
		read DUMMY
	fi
}
 

confirm_uninstall()
{
    echo "The agent will be stopped and removed from the system. Continue? (y/n): "
    read DUMMY
    if [ ! -z "$DUMMY" ] && [ "$DUMMY" == "y" -o "$DUMMY" == "yes" ]; then
        log_install "User started uninstalling process!"
        return 0
    else
        log_install "User cancelled the uninstalling process."
        echo "Uninstalling process is aborted. Press enter to continue."
        read DUMMY
        return 1
    fi
}

# Walk user through the installation
# require user interactive and must enter parameters one by one
wizard()
{
	ERRMSG=""
	SELECTION="-1"
	ACTION=""

    #continue draw menu selection till user quit
   	while [ $SELECTION -ne 0 ] ; do

        clear

        if [ -n "$ERRMSG" ] ; then
                echo "$ERRMSG"
                ERRMSG=""
        fi

        # determine which menu to draw ""
		case $MENU_LEVEL in
			1 ) print_menu
				if [ ! -d "$LOG_DIR" ]; then
					mkdir $LOG_DIR
				fi
				;;
			2 ) check_installationdata
				SELECTIONXML=""
				if [ $installationdata -eq 1 ]; then
					read SELECTIONXML
				fi
				if [ "$SELECTIONXML" == "y" -o "$SELECTIONXML" == "Y" ]; then
					log_message "Analyzing installation parameters from InstallationData.xml"
					MENU_LEVEL=1
					install
					retCode=$?
					if [ $retCode -ne 0 ]; then
						log_install "ERROR: unable to install packages ($retCode)"
						read DUMMY
					fi
					BLOCKING=0
					SELECTION="-1"
					continue
				else
					clear
					print_select1
				fi
				;;
			3 ) print_select2
				;;

			* ) echo "Invalid Menu[$MENU_LEVEL]"
				MENU_LEVEL=1
				;;
		esac

        # action to take based on user's selection
        read SELECTION
        ACTION="$MENU_LEVEL.$SELECTION"
        case $ACTION in
        	"1.1" )
                # this is the begining of the installation
                reset_data
				print_select1
            	;;
            "1.2" )
                confirm_uninstall
                if [ $? -ne 0 ]; then
                    continue
                fi
				uninstall &
				spinner "$!" "uninstalling ..."
				if [ $? -ne 0 -o ${PIPESTATUS[0]} -ne 0 ]; then
				    BLOCKING=0
					return 2
				fi
				# if ok, we should go back to main menu
				MENU_LEVEL=1
				BLOCKING=0
				;;
			"1.3" )
				SELECTION="0";true #quit
				;;

			"2.1" ) #install using activation key
				get_activateKey
				process_activation
				if [ $? -ne 0 ]; then
            		echo "Unable to process activation key $ACTIVATE_KEY"
					read DUMMY
				else
					install
					retCode=$?
					if [ $retCode -ne 0 ]; then
						log_install "ERROR: unable to install packages ($retCode)"
						read DUMMY
					fi
					BLOCKING=0
				fi
				MENU_LEVEL=1
				;;
			"2.2" ) #install using customer's info
#				print_select2
#                ;;
#			"2.3" ) #quit
#				SELECTION="0";true
#				;;

#			"3.1" )
				get_customer_name
				get_customer_ID
				get_registration_token
				get_server_prms
				get_backup_server
				MENU_LEVEL=1
				install
					retCode=$?
					if [ $retCode -ne 0 ]; then
						log_install "ERROR: unable to install packages ($retCode)"
					read DUMMY
				fi
				BLOCKING=0
				;;
#			"3.2" )
#				get_customer_ID
#				get_server_prms
#				get_backup_server
#				MENU_LEVEL=1
#				install
#					retCode=$?
#					if [ $retCode -ne 0 ]; then
#						log_install "ERROR: unable to install packages ($retCode)"
#					read DUMMY
#				fi
#				BLOCKING=0
#				;;
			"2.3" ) #quit
				SELECTION="0";true
				;;

        	* ) #invalid selection
				ERRMSG="Error: Invalid selection from menu"
                ;;
        esac
	done


}  

# END of INSTALLATION CALLS





# MAIN LOOP -----------------------------------------------------------------------

# delete all installation log and mark the new start
log_install ""
log_install ""
log_install "setup script started -------------------------------------------------"

#should we run the wizard
if [ $# -eq 0 ]; then
	INTERACTIVE=1
	wizard
else
	INTERACTIVE=0
	log_install "we run install in silent mode ..."

	# process the arguments
	while getopts 'k:c:i:s:p:a:x:r:t:uh' OPTION
	do
		case $OPTION in
		k)	ACTIVATE_KEY=$OPTARG
			;;
		c)	CNAME=$OPTARG
			;;
		i)	CID=$OPTARG
			;;
		s)	SERVER=$OPTARG
			;;
		p)	PROTOCOL=$OPTARG
			;;
		a)	PORT=$OPTARG
			;;
		x)	PROXY=$OPTARG
			;;
		t)	REGISTRATION_TOKEN=$OPTARG
			;;
		u)  confirm_uninstall
            if [ $? -ne 0 ]; then
                exit 0
            fi
		    uninstall > $BG_ERROR_FILE 2>&1 &
    		spinner "$!" "uninstalling ..."
    		process_bg_msg
    		if [ $? -ne 0 -o ${PIPESTATUS[0]} -ne 0 ]; then
    			exit 1
    		else
    		    echo "Uninstall completed."
    		fi
    		BLOCKING=0
            exit 0
		    ;;
		r)  ACTIVATE_KEY=$OPTARG
		    process_activation
		    if [ $? -ne 0 ]; then
                echo "Unable to process activation key $ACTIVATE_KEY"
			    exit 1
		    fi
		    update_conf
		    log_message "Configuration file is updated."
		    exit 0
		    ;;
		?)	print_usage
			exit 2
			;;
		esac
	done

	# the rest of the arguments
	shift $(($OPTIND - 1))

	if [ -z $ACTIVATE_KEY ]; then
		log_install "Install with custom parameters."
	else
		process_activation 
		if [ $? -ne 0 ]; then
            echo "Unable to process activation key $ACTIVATE_KEY"
			exit 1
		fi
	fi

	# got all arguments
	install
	retCode=$?
	if [ $retCode -ne 0 -o ${PIPESTATUS[0]} -ne 0 ]; then
		log_message "ERROR: Installation failed ($retCode)"

		if [ $INTERACTIVE -eq 1 ]; then
			read DUMMY
		fi
	else
		if [ -f /bin/systemctl ]; then
			echo "Switch to systemd"
			echo -e '[Unit]\nDescription=N-able Agent\nAfter=cron.service network-manager.service\n[Service]\nEnvironment="LD_LIBRARY_PATH=/opt/nable/usr/lib/"\nExecStart=/usr/sbin/nagent -f /home/nagent/nagent.conf\nExecStartPost=/bin/bash -c "echo `pidof -s nagent` > /var/run/nagent.pid"\nExecStop=/bin/bash -c "if [ -f /var/run/nagent.pid ]; then rm -f /var/run/nagent.pid; fi"\nPIDFile=/var/run/nagent.pid\nRestart=always\n\nKillMode=process\n[Install]\nWantedBy=multi-user.target' > /lib/systemd/system/nagent.service
			ln -sf /lib/systemd/system/nagent.service /etc/systemd/system/multi-user.target.wants/nagent.service
			systemctl daemon-reload
			echo "enable nagent"
			systemctl enable nagent
			echo "start nagent"
			systemctl --no-block start nagent
		else
			echo "Switch to init.d"
			update-rc.d nagent defaults
			service nagent start
		fi
	fi
	BLOCKING=0
fi
   
log_install "setup script ended ----------------------------------------------------\n\n"
# END MAIN LOOP --------------------------------------------------------------------


exit 
