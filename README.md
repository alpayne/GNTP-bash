GNTP-bash
=========

Bash script for sending messages over GNTP to Growl

```
usage: gntp.sh [-H <host[:port]>] [-P <password>] [-rs] -a <APPNAME name> 
               -n <notification name> [-n <notification name]...

Program send messages via GNTP to Growl application listening on target host.

OPTIONS:

    -a --appname            Name of application in as it appears in Growl
    -d --displayname        Display name for notification in Growl
    -H --host               Host[:port] tp send message to (defaults to local host
                            and port 23053)
    -I --appicon            Application icon URL
    -i --icon               Notification icon URL (for preceding notification)
    -n --name               Notification name in Growl 
    -p --priority           Notification priority (range: -2 to 2, 0 is default)
    -P --password           Password (cannot be NULL when sending over network)
    -r --register           Send registration message
    -s --sticky             Make notification sticky
    -T --title              Title to display in notification window
    -t --text               Text to display in notification window (defaults to "")  

    -h --help               Show this help

Growl requires applications to register before it will display notifications. Multiple
notification names (and optional icons & display names) can be registered at once. A
registration message overwrites the previous registration configuration for an 
application.  

EXAMPLES:

Register an application on the localhost:

    gntp.sh -r -a "App Name" -n "startup" -i "http://.../startupicon.png" -n "shutdown"

Send a notification to the localhost:

    gntp.sh -a "App Name" -n "startup" -T "App Name Starting" -t "Application started"

```
