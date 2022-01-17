#!/bin/bash

# Exit on failure --------------------------------------------------------------
function exitOnFailure {
	echo "" >> $LOGGER
 	echo "Download failed" >> $LOGGER
	echo "==================================== END DOWNLOAD ================================" >> $LOGGER
  	exit 1
}

# Show usage -------------------------------------------------------------------
function usage {
	echo "" >> $LOGGER
	echo "Usage: nagent_download.sh URL InstallerName FileSize MD5Sum Destination [Proxy] [ProxyUsername] [ProxyPassword]" >> $LOGGER
	echo "Example: nagent_download.sh http://192.168.20.128/download/100.0.0.0/ubuntu16_18_64/N-central/nagent-ubuntu16_18_64.tar.gz nagent-ubuntu16_18_64.tar.gz 2785964 aea43c12d2a86d76ea95bbbf0bf625e9 /tmp" >> $LOGGER

  	exitOnFailure
}

# Verify given arguments -------------------------------------------------------
function verifyArguments {
	if [ -z "$URL" ]
	then
  		echo "No download url provided" >> $LOGGER 
  		usage
	fi	
	
	if [ -z "$INSTALLER" ]
	then
  		echo "No installer name provided" >> $LOGGER
  		usage
	fi

	if [ -z "$INSTALLER_FILESIZE" ]
	then 
  		echo "No filesize provided for $INSTALLER" >> $LOGGER
  		usage
	fi

	if [ -z "$INSTALLER_CHECKSUM" ]
	then
  		echo "No checksum provided for $INSTALLER" >> $LOGGER
  		usage
	fi
	
	if [ -z "$DESTINATION" ]
	then
		echo "No destination folder provided" >> $LOGGER
		usage
	fi
}

# Download agent installer -----------------------------------------------------
function download {
	# Find complete download installer file path
    DESTINATION_FILE="${DESTINATION}/${INSTALLER}"

    # Find complete download extracted installer folder path
    NAME=(`echo $INSTALLER | tr '.' ' '`)
    LENGTH=${#NAME[@]}
    DIR_NAME=""
    for (( c=0; c<LENGTH-2; c++))
    do      
    	if [ "$c" = 0 ]; then
        	DIR_NAME=${NAME[c]}
        else
        	DOT="."
            DIR_NAME=$DIR_NAME$DOT${NAME[c]}
        fi
	done
    DESTINATION_DIR="${DESTINATION}/${DIR_NAME}"

    # Delete agent installer and extracted directory where new agent will be downloaded and extracted to
    rm -rf $INSTALLER
    rm -rf $DESTINATION_FILE
    rm -rf $DESTINATION_DIR

	# Call wget to download agent
	echo "" >> $LOGGER

	if [ ! -z "$PROXY" ] && [ ! -z "$PROXY_USERNAME" ] && [ ! -z "$PROXY_PASSWORD" ]; then
		if [ $DOWNLOADER -eq 1 ]; then
			echo "wget -e http_proxy=$PROXY --proxy-user=$PROXY_USERNAME --proxy-password=$PROXY_PASSWORD --no-check-certificate $URL" >> $LOGGER 
			wget -e http_proxy=$PROXY --proxy-user=$PROXY_USERNAME --proxy-password=$PROXY_PASSWORD --no-check-certificate $URL 2>> $LOGGER
		else
			echo "curl -OL -k -x $PROXY -U $PROXY_USERNAME:$PROXY_PASSWORD $URL" >> $LOGGER
			curl -OL -k -x $PROXY -U $PROXY_USERNAME:$PROXY_PASSWORD $URL 2>> $LOGGER
		fi
	elif [ ! -z "$PROXY" ] && [ ! -z "$PROXY_USERNAME" ]; then
		if [ $DOWNLOADER -eq 1 ]; then
			echo "wget -e http_proxy=$PROXY --proxy-user=$PROXY_USERNAME --no-check-certificate $URL" >> $LOGGER 
			wget -e http_proxy=$PROXY --proxy-user=$PROXY_USERNAME --no-check-certificate $URL 2>> $LOGGER
		else
			echo "curl -OL -k -x $PROXY -U $PROXY_USERNAME $URL" >> $LOGGER
			curl -OL -k -x $PROXY -U $PROXY_USERNAME $URL 2>> $LOGGER
		fi
	elif [ ! -z "$PROXY" ]; then
		if [ $DOWNLOADER -eq 1 ]; then
			echo "wget -e http_proxy=$PROXY --no-check-certificate $URL" >> $LOGGER 
			wget -e http_proxy=$PROXY --no-check-certificate $URL 2>> $LOGGER
		else
			echo "curl -OL -k -x $PROXY $URL" >> $LOGGER
			curl -OL -k -x $PROXY $URL 2>> $LOGGER
		fi
	else
		if [ $DOWNLOADER -eq 1 ]; then
			echo "wget --no-check-certificate $URL" >> $LOGGER
			wget --no-check-certificate $URL 2>> $LOGGER
		else
			echo "curl -OL -k $URL" >> $LOGGER
			curl -OL -k $URL 2>> $LOGGER
		fi
	fi
	
	# Verify filesize
	FILESIZE=$(stat -c %s "$INSTALLER_PATH" 2>> $LOGGER) 
	if [ "$FILESIZE" != "$INSTALLER_FILESIZE" ]
	then
		echo "Downloaded $INSTALLER filesize $FILESIZE != given filesize $INSTALLER_FILESIZE" >> $LOGGER
		exitOnFailure
	fi
	echo "Downloaded $INSTALLER filesize $FILESIZE == given filesize $INSTALLER_FILESIZE" >> $LOGGER

	# Verify md5 checksum
	FULL_CHECKSUM=$(md5sum "$INSTALLER_PATH")
	SPLIT_CHECKSUM=(`echo "$FULL_CHECKSUM" | tr '=' ' '`)
	CHECKSUM=${SPLIT_CHECKSUM[0]}
	if [ "$CHECKSUM" != "$INSTALLER_CHECKSUM" ]
	then
		echo "Downloaded $INSTALLER checksum $CHECKSUM != given checksum $INSTALLER_CHECKSUM" >> $LOGGER
		exitOnFailure
	fi
	
	echo "Downloaded $INSTALLER checksum $CHECKSUM == given checksum $INSTALLER_CHECKSUM" >> $LOGGER
}

# Unarchive the tarball --------------------------------------------------------
function moveAndUntar {
	echo "" >> $LOGGER
	echo "--> Unarchive the installer" >> $LOGGER
	
	mv -f $INSTALLER $DESTINATION 2>> $LOGGER
	echo "Moved $INSTALLER to $DESTINATION" >> $LOGGER
	
	tar -C $DESTINATION -xvf "${DESTINATION}/${INSTALLER}" >> $LOGGER 2>> $LOGGER
}

# Step 1: Setup logger
LOGGER="/tmp/nagent-upgrade.log"
echo "" >> $LOGGER
echo "================= START DOWNLOAD $(date) =================" >> $LOGGER

# Step 2: Verify if wget or curl are installed
DOWNLOADER=0
if [ -n "$(which wget)" ]; then
	DOWNLOADER=1
fi
if [ $DOWNLOADER -eq 0 ]; then
	if [ -n "$(which curl)" ]; then
		DOWNLOADER=2
	fi
fi
if [ $DOWNLOADER -eq 0 ]; then
	echo "wget or curl not found" >> $LOGGER
	exitOnFailure
fi

# Step 3. Verify given arguments
URL=$1
INSTALLER=$2
INSTALLER_FILESIZE=$3
INSTALLER_CHECKSUM=$4
DESTINATION=$5
verifyArguments

# proxy arguments are optional
PROXY=$6
PROXY_USERNAME=$7
PROXY_PASSWORD=$8

INSTALLER_PATH="${PWD}/${INSTALLER}"

echo "--> Using following variables" >> $LOGGER
echo "URL=$URL" >> $LOGGER
echo "INSTALLER=$INSTALLER" >> $LOGGER
echo "INSTALLER_FILESIZE=$INSTALLER_FILESIZE" >> $LOGGER
echo "INSTALLER_CHECKSUM=$INSTALLER_CHECKSUM" >> $LOGGER
echo "DESTINATION=$DESTINATION" >> $LOGGER
echo "INSTALLER_PATH=$INSTALLER_PATH" >> $LOGGER
echo "PROXY=$PROXY" >> $LOGGER
echo "PROXY_USERNAME=$PROXY_USERNAME" >> $LOGGER
echo "PROXY_PASSWORD=$PROXY_PASSWORD" >> $LOGGER

# Step 4. Download and verify agent installer
download

# Step 5. Move agent to destination 
moveAndUntar

echo "" >> $LOGGER
echo "Download successfull" >> $LOGGER
echo "==================================== END DOWNLOAD ================================" >> $LOGGER
