#!/bin/bash

# Register APPNAME with Growl and send notifications.

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Should script use Netcat? Set USE_NETCAT to 1. (Slightly slower)
readonly USE_NETCAT=0
# To generate the password hash, this script looks for openssl, sha256sum, 
# md5sum, or md5 (for OSX), and uses the first found. To override the default
# set HASHCOMMAND to the appropriate command.
readonly HASHCOMMAND=""
# Growl supports encrypted notifications. To enable encryption set ENCRYPT to 1
# and set ENCRYPT_CMD to the appropriate command.
readonly ENCRYPT=1

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
    if [[ "MODE" == "REGISTER" ]]; then
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

generate_key () {
    local password="$@"

    # The following procedure is used when converting a password to a key:
    #
    # 1. The password is converted an UTF8 byte array
    # 2. A cyptographically secure salt is generated (should be between 4 and
    #    16 bytes)
    # 3. The salt bytes are appended to the password bytes to form the key 
    #    basis
    # 4. The key is generated by computing the hash of the key basis using 
    #    one of the supported hashing algorithms
    # 5. The key hash is produced by computing the hash of the key (using 
    #    the same hashing algorithm used in step 4) and hex-encoding it to 
    #    a fixed-length string


    # 1. Generate a reasonbly secure salt and trim it to 16 bytes
    local salt=$( date | md5 | base64 )   
    salt=${salt:0:16}    
    local hexsalt=$( printf "%s" "$salt" | xxd -p )
    
    # 2. Append salt bytes to password bytes to form key basis
    local keybasis="$password$salt"
    # 3. Compute the hash of the key basis 
    local key=$( printf "%s" "$keybasis" | gsha256sum )
    key=${key:0:32}
    # 4. Compute the hash of the key (note key should not be hex encoded at 
    #    this point, or as a work around we use xxd -r).
    local keyhash=$( printf "%s" "$key" | xxd -r -p | gsha256sum )
    # 5. Convert the salt to a hex string.

    printf "%s" "SHA256:$keyhash.$hexsalt"
}

send_gntp () {
    msg="$1" 
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
}

# -----------------------------------------------------------------------------
# Main 
# -----------------------------------------------------------------------------

readonly PROGNAME=$(basename "$0")

cmdline "$@"

if [[ -n $PASSWORD ]]; then
    keystring=$(generate_key "$PASSWORD")
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
    printf -v msg_header "GNTP/1.0 $MODE NONE %s\r\n" "$keystring" 

printf -v msg_text "%b%b" "$msg_header" "$msg_body"
send_gntp "$msg_text"

