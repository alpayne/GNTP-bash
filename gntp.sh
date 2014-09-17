#!/bin/bash

# Register APPNAME with Growl and send notifications.

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Should script use Netcat? Set USE_NETCAT to 1. (Slightly slower)
readonly USE_NETCAT=0
# To generate the password hash, this script looks for openssl, sha256sum, 
# md5sum, or md5 (for OSX), and uses the first found. To override the default
# set HASHCOMMAND to the appropriate command and HASHTYPE to the type of hash.
readonly HASHCOMMAND=""
readonly HASHTYPE=""

# -----------------------------------------------------------------------------
# Function definitions 
# -----------------------------------------------------------------------------

usage() {
    cat <<- EOF

    usage: $PROGNAME [-H <host[:port]>] [-P <password>] [-rs] -a <APPNAME name> -n <notification name> [-n <notification name]... 

    Program send messages via GNTP to Growl APPNAME listening on target host.

    OPTIONS:

        -a --appname            Name of APPNAME in as it appears in Growl
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
    
        $PROGNAME -r -a "App Name" -n "startup" -i "http://.../startupicon.png" -n "shutdown"

    Send a notification to the localhost:

        $PROGNAME -a "App Name" -n "startup" -T "App Name Starting" -t "Application started successfuly"

EOF
    exit 0
}

cmdline() {
    while getopts "a:d:H:I:i:n:P:p:rsT:t:-:h" optchar; do
        case "${optchar}" in
            -)
                case "${OPTARG}" in
                    help) 
                        usage
                        exit 2
                        ;;
                    register)
                        readonly MODE="REGISTER" 
                        ;;
                    host=*)
                        readonly HOST=${OPTARG%:*}      # strip off : and trailing TEXT
                        readonly PORT=${OPTARG#*:}      # strip off leading TEXT to :
                        ;;
                    appname=*)
                        readonly APPNAME="$OPTARG"
                        ;;
                    appicon=*)
                        readonly APPICON="$OPTARG"
                        ;;
                    name=*)
                        names+=( "$OPTARG" )
                        ;;
                    displayname=*)
                        displaynames[${#names[@]}-1]="$OPTARG"
                        ;;
                    icon=*)
                        icons[${#names[@]}-1]="$OPTARG"
                        ;;
                    password=*)
                        readonly PASSWORD="$OPTARG"
                        ;;
                    priority=*)
                        readonly PRIORITY="$OPTARG"
                        ;;
                    sticky)
                        readonly STICKY="Yes"
                        ;;
                    title=*)
                        readonly TITLE="$OPTARG"
                        ;;
                    text=*)
                        readonly TEXT="$OPTARG"
                        ;;
                    *)
                        if [ "$OPTERR" = 1 ] && [ "${optspec:0:1}" != ":" ]; then
                            echo "Unknown option --${OPTARG}" >&2
                            usage
                        fi
                        ;;
                esac;;
            h)  # Help! display usage.
                usage
                exit 2
                ;;
            r)  # Register flag
                readonly MODE="REGISTER" 
                ;;
            H)  # Host & IP
                readonly HOST=${OPTARG%:*}      # strip off : and trailing TEXT
                readonly PORT=${OPTARG#*:}      # strip off leading TEXT to :
                ;;
            a)  # Application name
                readonly APPNAME="$OPTARG"
                ;; 
            I)  # Application icon
                readonly APPICON="$OPTARG"
                ;;
            n)  # Notifiction name
                names+=( "$OPTARG" )
                ;;
            d)  # Notification display name
                displaynames[${#names[@]}-1]="$OPTARG"
                ;;
            i)  # Notification icon
                icons[${#names[@]}-1]=( "$OPTARG" )
                ;;
            P)  # Password
                readonly PASSWORD="$OPTARG"
                ;;
            p)  # Priority
                readonly PRIORITY="$OPTARG"
                ;;
            s)  # Sticky 
                readonly STICKY="Yes"
                ;;
            T)  # Title
                readonly TITLE="$OPTARG"
                ;;
            t)  # Message TEXT
                readonly TEXT="$OPTARG"
                ;;
            *)
                if [ "$OPTERR" != 1 ] || [ "${optspec:0:1}" = ":" ]; then
                    echo "Non-option argument: '-${OPTARG}'" >&2
                    usage
                fi
                ;;
        esac
    done
    if [[ "$MODE" == "REGISTER" ]]; then
        if [[ -z $APPNAME || ${#names[@]} -eq 0 ]]; then
            echo "$PROGNAME requires APPNAME name and notifications list to register."
            echo
            usage      
        fi
    else
        if [[ -z $APPNAME || ${#names[@]} -eq 0 || -z $TITLE ]]; then
            echo "$PROGNAME requires APPNAME name and notification to send to Growl."
            echo
            usage      
        fi
    fi
}

# -----------------------------------------------------------------------------
# Main 
# -----------------------------------------------------------------------------

readonly PROGNAME=$(basename "$0")

# Convoluted search for hash program.
if hash "$HASHCOMMAND" 2>/dev/null; then
    hashcommand="$HASHCOMMAND"
    hashtype="$HASHTYPE"
elif hash openssl 2>/dev/null; then
    hashcommand="openssl dgst -sha256"
    hashtype="SHA256"
elif hash sha256sum 2>/dev/null; then
    hashcommand="sha256sum"
    hashtype="SHA256"
elif hash gsha256sum 2>/dev/null; then
    hashcommand="gsha256sum"
    hashtype="SHA256"
elif hash md5sum 2>/dev/null; then
    hashcommand="md5sum"
    hashtype="MD5"
elif hash gmd5sum 2>/dev/null; then
    hashcommand="gmd5sum"
    hashtype="MD5"
elif hash md5sum 2>/dev/null; then
    hashcommand="md5sum"
    hashtype="MD5"
elif hash md5 2>/dev/null; then
    hashcommand="md5"
    hashtype="MD5"
else 
     echo "Unable to find suitable hash program. Please set \$HASHCOMMAND in $PROGNAME"
     exit 1
fi

if [[ "$hashcommand" == "*sha256" ]]; then
    hashtype="SHA256"
elif [[ "$hashcommand" == "*md5*" ]]; then
    hashtype="MD5"
elif [[ -z "$hashcommand" ]]; then
    echo "Invalid hash type set."
    exit 1
fi
cmdline "$@"

if [[ -n $PASSWORD ]]; then
    # Generate the key, using the follow procedure:
    #
    # 1. Generate a reasonbly secure salt and trim it to 16 bytes
    salt=$( date | $hashcommand | base64 )   
    salt=${salt:0:16}    
    hexsalt=$( printf "%s" "$salt" | xxd -p )
    # 2. Append salt bytes to password bytes to form key basis
    keybasis="$PASSWORD$salt"
    # 3. Compute the hash of the key basis 
    key=$( printf "%s" "$keybasis" | $hashcommand )
    key=${key% *}
    # 4. Compute the hash of the key (note key should not be hex encoded at 
    #    this point, or as a work around we use xxd -r).
    keyhash=$( printf "%s" "$key" | xxd -r -p | $hashcommand )
    keyhash=${keyhash% *}
    # 5. Convert the salt to a hex string.
    printf -v keystring "%s:%s.%s" "$hashtype" "$keyhash" "$hexsalt"
else
    keystring="NONE"
fi
if [[ "$MODE" == "REGISTER" ]]; then
    msg_body=$( printf "Application-Name: %s\r\n" "$APPNAME"
                printf "Application-Icon: %s\r\n" "$APPICON"
                printf "Notifications-Count: %s\r\n" "${#names[@]}"
                count=0
                for i in "${names[@]}"; do
                    printf "\r\nNotification-Name: %s\r\n" "$i"
                    [[ -n ${icons[$count]} ]] && \
                        printf "Notification-Icon: %s\r\n" "${icons[$count]}"
                    [[ -n ${displaynames[$count]} ]] && \
                        printf "Notification-Display-Name: %s\r\n" "${displaynames[$count]}"
                    printf "Notification-Enabled: True\r\n"
                    (( count += 1 ))
                done
                printf "\r\n\r\n" )
else
    MODE="NOTIFY"
    msg_body=$( printf "Application-Name: %s\r\n" "$APPNAME"
                printf "Notification-Name: %s\r\n" "${names[0]}"
                printf "Notification-Title: %s\r\n" "$TITLE"
                printf "Notification-Text: %s\r\n" "$TEXT"
                printf "Notification-Sticky: %s\r\n" "${STICKY:-No}"
                printf "\r\n\r\n" )
fi

printf -v msg_header "GNTP/1.0 %s NONE %s" "$MODE" "$keystring" 
printf -v msg "%b\r\n%b" "$msg_header" "$msg_body"

# Send GNTP message
if [[ $USE_NETCAT -eq 1 ]] && hash nc 2>/dev/null; then
    IFS=$'\n'
    result=( $(printf "%b" "$msg" | nc -w 1 127.0.0.1 23053 ) )
else
    exec 10<>/dev/tcp/127.0.0.1/23053
    printf "%b" "$msg"  >&10
    read -u 10 result[0]
    read -u 10 result[1]
    read -u 10 result[2]
    exec 10>&- # close output connection
    exec 10<&- # close input connection
fi
if [[ "${result[0]}" == *-ERROR* ]]; then
    echo ${result[1]}
    echo ${result[2]}
    exit 1
else
    exit 0
fi


