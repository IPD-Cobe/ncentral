#!/bin/bash

# Must install as root/sudo
if [ `id -ur` -ne 0 ]; then
        echo "Insufficient permissions. Run as root"
        exit
fi

INPUT=$1

confirm_uninstall()
{
        if [ -z $INPUT ]; then
                printf "The agent will be stopped and removed from the system. Continue? [y/n]: "
                read ANSWER
        else
                ANSWER=$INPUT
        fi

        if [ ! -z "$ANSWER" ] && [ "$ANSWER" == "y" -o "$ANSWER" == "yes" ]; then
                return 0
        else
                return 1
        fi
}

uninstall()
{
    echo ""

    # Step 1: Stop agent service
    printf "%-40s" "Stopping agent service:"

    if [ -f /bin/systemctl ]; then
        echo "Stop agent and delete systemd items"
        systemctl stop nagent
        rm -f /lib/systemd/system/nagent.service
        systemctl daemon-reload
    else
        echo "Stop nagent"
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

    # Step 2a: Optional for systemd only
    if [ -f /bin/systemctl ]; then
        echo "Delete systemd items"
        rm -f /usr/lib/systemd/system/nagent.service
        echo "Clean /home/nagent"
        rm -f /home/nagent/lib*.so
        rm -f /home/nagent/nagent*
    else
        echo "Delete init.d items"
        rm -f /etc/init.d/nagent
        rm -f /home/nagent/lib*.so
        rm -f /home/nagent/nagent*
    fi
    # Step 3: Cleanup left over folders
    rm -rf /var/log/n-central
    rm -f /opt/nable/usr/lib/lib*.so
    # Step 4: Cleanup crontab
    sed '/ root logrotate \/etc\/logrotate.d\/nagent/d' /etc/crontab > /tmp/crontab
    sed '/ root run-parts \/etc\/cron.fivem/d' /tmp/crontab > /tmp/crontab1
    cp -f /tmp/crontab1 /etc/crontab
    rm -f /tmp/crontab*
}

confirm_uninstall
if [ $? -ne 0 ]; then
        exit
fi

uninstall

echo ""
echo "Finished agent uninstall"
