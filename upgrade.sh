#!/bin/bash

# Determine if this scipt is run by root user ----------------------------------
function isRoot {
 	if [ $(id -u) != '0' ] ; then
	 	echo "Run this script as root" >> $LOGGER
	 	return 1
 	fi
 	
 	return 0
} 

# Do cleanup work and exit the script with error code --------------------------
function exitOnFailure {
	echo "" >> $LOGGER
	
	echo "rm -rf $BACKUP" >> $LOGGER
	`rm -rf $BACKUP 2>> $LOGGER`
	
	echo "mv -f $DOWNLOADTAR $DOWNLOADTAROLD" >> $LOGGER
	`mv -f $DOWNLOADTAR $DOWNLOADTAROLD 2>> $LOGGER`
	echo "rm -rf $DOWNLOAD" >> $LOGGER
	`rm -rf $DOWNLOAD 2>> $LOGGER`
	echo "Agent upgrade failed" >> $LOGGER
	echo "================================== END UPGRADE ============================" >> $LOGGER
	exit 1
}

# Backup agent config, log files, and pending submit data ----------------------
function backup {
	echo "" >> $LOGGER
	echo "Backing up the needed data" >> $LOGGER
	
	`mkdir $BACKUP 2>> $LOGGER` 
	`cp $HOME/nagent.conf $BACKUP 2>> $LOGGER`
	`cp $HOME/nagent.conf.Save $BACKUP 2>> $LOGGER`
	`cp -rf $LOG_DIR $BACKUP 2>> $LOGGER`
	`cp -rf $HOME/CMData $BACKUP 2>> $LOGGER`
	`cp -rf $HOME/CMSetting $BACKUP 2>> $LOGGER`
}

# Uninstall existing agent -----------------------------------------------------
function uninstall {
	echo "" >> $LOGGER
	echo "Uninstalling the agent" >> $LOGGER
	
	echo "$HOME/uninstall.sh y" >> $LOGGER 
	$HOME/uninstall.sh y >> $LOGGER 2>> $LOGGER
}

# Install new agent rpms and restore backed up data ----------------------------
function install() 	
{
	echo "" >> $LOGGER
	echo "Installing new agent" >> $LOGGER
	
    dpkg -i $DOWNLOAD/nagent.deb
    retCode=$?
    if [ $retCode -ne 0 ]; then
        echo "ERROR: Failed to install nagent ($retCode)" >> $LOGGER
        exit $retCode
		exitOnFailure
    fi
    
    # Copy backup files
	echo "Copying backup files" >> $LOGGER
	`cp $BACKUP/nagent.conf $HOME/nagent.conf 2>> $LOGGER`
	`cp $BACKUP/nagent.conf.Save $HOME/nagent.conf.Save 2>> $LOGGER`
	`cp -rf $BACKUP/n-central $LOG_LOCATION 2>> $LOGGER`
	`cp -rf $BACKUP/CMData $HOME 2>> $LOGGER`
	`cp -rf $BACKUP/CMSetting $HOME 2>> $LOGGER`
	`cp $DOWNLOAD/uninstall.sh $HOME 2>> $LOGGER`
    `cp $DOWNLOAD/nagent_download.sh $HOME 2>> $LOGGER`

	return 0
}

# Starts agent service ---------------------------------------------------------
function startAgent {
	echo "" >> $LOGGER
	if [ -f /bin/systemctl ]; then
		echo "Switch to systemd"
		echo -e '[Unit]\nDescription=N-able Agent\nAfter=cron.service network-manager.service\n[Service]\nEnvironment="LD_LIBRARY_PATH=/opt/nable/usr/lib/"\nExecStart=/usr/sbin/nagent -f /home/nagent/nagent.conf\nExecStartPost=/bin/bash -c "echo `pidof -s nagent` > /var/run/nagent.pid"\nExecStop=/bin/bash -c "if [ -f /var/run/nagent.pid ]; then rm -f /var/run/nagent.pid; fi"\nPIDFile=/var/run/nagent.pid\nRestart=always\n\nKillMode=process\n[Install]\nWantedBy=multi-user.target' > /lib/systemd/system/nagent.service
		ln -sf /usr/lib/systemd/system/nagent.service /etc/systemd/system/multi-user.target.wants/nagent.service
		systemctl enable nagent
		`systemctl start nagent >> $LOGGER 2>> $LOGGER`
	else	
		echo "Switch to initd"
		update-rc.d nagent defaults
		`/usr/sbin/service nagent start >> $LOGGER 2>> $LOGGER`
	fi
	chmod 644 /etc/logrotate.d/nagent
	if ! `grep -q 'root logrotate /etc/logrotate.d/nagent' /etc/crontab`
	then
		echo  "*/9 * * * * root logrotate /etc/logrotate.d/nagent >/dev/null" >> /etc/crontab
	fi
        if ! `grep -q 'root run-parts /etc/cron.fivem' /etc/crontab`
        then
                echo  "*/5 * * * * root run-parts /etc/cron.fivem" >> /etc/crontab
        fi
	retCode=$?
	if [ $retCode -ne 0 ]; then
		echo "ERROR: unable to start nagent service. $retCode" >> $LOGGER
	    exitOnFailure
	fi
}

LOGGER="/tmp/nagent-upgrade.log"
echo "" >> $LOGGER
echo "======================== START UPGRADE $(date) ===========================" >> $LOGGER

# Step 1: Ensure script is run with sufficient priviledges
isRoot
if [ $? != 0 ]; then
	exitOnFailure
fi

DOWNLOAD="/tmp/nagent-ubuntu16_64"
DOWNLOADTAR="/tmp/nagent-ubuntu16_18_64.tar.gz"
DOWNLOADTAROLD="/tmp/nagent-ubuntu16_64-old.tar.gz"
BACKUP="/tmp/nagent-upgrade-backup"
HOME="/home/nagent"
LOG_DIR="/var/log/n-central"
LOG_LOCATION="/var/log"

echo "Using following variables" >> $LOGGER
echo "DOWNLOADTAR=$DOWNLOADTAR" >> $LOGGER
echo "DOWNLOAD=$DOWNLOAD" >> $LOGGER
echo "DOWNLOADTAROLD=$DOWNLOADTAROLD" >> $LOGGER
echo "BACKUP=$BACKUP" >> $LOGGER
echo "HOME=$HOME" >> $LOGGER
echo "LOG_DIR=$LOG_DIR" >> $LOGGER
echo "LOG_LOCATION=$LOG_LOCATION" >> $LOGGER

# Step 2: Backup needed data ---------------------------------------------------
backup

# For Ubuntu check nagent.service file
NAGENT_SERVICE=/usr/lib/systemd/system/nagent.service
if [ -f $NAGENT_SERVICE ]; then
        echo "nagent.service exists"
        if grep -Fxq KillMode=process $NAGENT_SERVICE; then
                echo "KillMode=process exists"
        else
                echo "KillMode=process does not exist"
                sed '/Restart=always/a KillMode=process' $NAGENT_SERVICE >> $NAGENT_SERVICE
                systemctl daemon-reload
        fi
else
        echo "nagent.service does not exist"
        echo -e '[Unit]\nDescription=N-able Agent\nAfter=crond.service network.target\n[Service]\nExecStart=/usr/sbin/nagent -f /home/nagent/nagent.conf\nExecStartPost=/bin/bash -c "echo `pidof -s nagent` > /var/run/nagent.pid"\nExecStop=/bin/bash -c "if [ -f /var/run/nagent.pid ]; then rm -f /var/run/nagent.pid; fi"\nPIDFile=/var/run/nagent.pid\nRestart=always\nKillMode=process\n[Install]\nWantedBy=multi-user.target' >$NAGENT_SERVICE
        systemctl daemon-reload
fi

# Step 3: Uninstall existing agent ---------------------------------------------
uninstall

# Step 4: Remove modules libraries if any
echo "rm -f $HOME/lib*.so" >> $LOGGER
rm -f $HOME/lib*.so

# Step 5: Install new agent ----------------------------------------------------
install
if [ $? != 0 ] ; then
	echo "Failed to install new agent" >> $LOGGER
	exitOnFailure
fi

# Step 6: Start agent service --------------------------------------------------
startAgent

# Step 7: Remove backed up data ------------------------------------------------
echo "" >> $LOGGER
echo "Removing backup data" >> $LOGGER
echo "rm -rf $BACKUP" >> $LOGGER
`rm -rf $BACKUP 2>> $LOGGER`
echo "Removing installer" >> $LOGGER
echo "rm -rf $DOWNLOADTAR" >> $LOGGER
`rm -f $DOWNLOADTAR 2>> $LOGGER`
echo "rm -rf $DOWNLOAD" >> $LOGGER
`rm -rf $DOWNLOAD 2>> $LOGGER`

if [ -f $DOWNLOADTAROLD ]; then
echo "rm -f $DOWNLOADTAROLD" >> $LOGGER
`rm -f $DOWNLOADTAROLD 2>> $LOGGER`
fi

echo "" >> $LOGGER
echo "Upgrade successfull" >> $LOGGER
echo "============================== END UPGRADE ===============================" >> $LOGGER
