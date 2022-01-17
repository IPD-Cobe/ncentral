Installing the Ubuntu Linux Agent (nagent) service
Before installing, you need the following:
1.	ROOT access
2.	Bash shell

Note: This service also requires Open SSH for public-key authentication. 
If it is not detected during installation, it will be installed automatically with the nagent service.


To install the N-agent
1.	Login as ROOT 
2.	Run ./install.sh

The script should be started from the directory where it is located.
The script runs the installation and starts the nagent service. For other installation options, run ./install.sh -h.
If the installation option 'customer name' has a space in it, it must be identified with quotation marks (for example, "Test Corp").
Note: Whenever the system is rebooted, the nagent service will start automatically.


