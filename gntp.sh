#!/bin/bash

# Register application with Growl

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly USENC=0     # set to 1 if you want script to use netcat (slightly slower)

readonly PROGNAME=$(basename "$0")

readonly MD5SUM=/usr/local/bin/gmd5sum
readonly SHA256SUM=/usr/local/bin/sha256sum


# -----------------------------------------------------------------------------
# Function definitions 
# -----------------------------------------------------------------------------

usage() {
    cat <<- EOF

    usage: $PROGNAME -a <application name> -n <notification name> [-n <notification name]... 

    Program send messages via GNTP to Growl application listening on target host.

    OPTIONS:
        -a --application        Name of application in Growl
        -r --register           Growl requires applications register before it
                                will display notifications
        -n --notification       Notification to display
        -P --password           Password (cannot be NULL when sending over 
                                network)
        -H --host               host[:port] tp send message to
        -p --priority
        -u --udp                Send via UDP instead of TCP
        -s --sticky
        -T --title
        -t --text

        -h --help               show this help


EOF
    exit 0
}

cmdline() {
    while getopts "ra:n:H:P:p:sut:T:-:" optchar; do
        case "${optchar}" in
            -)
                case "${OPTARG}" in
                    help) 
                        usage
                        exit 2
                        ;;
                    register)
                        readonly REGISTER=1
                        ;;
                    application=*)
                        readonly application="$OPTARG"
                        ;;
                    notification=*)
                        names+=( "$OPTARG" )
                        ;;
                    host=*)
                        readonly HOST=${OPTARG%:*}      # strip off : and trailing text
                        readonly PORT=${OPTARG#*:}      # strip off leading text to :
                        ;;
                    password=*)
                        readonly PASSWORD="$OPTARG"
                        ;;
                    priority=*)
                        readonly PRIORITY="$OPTARG"
                        ;;
                    sticky)
                        readonly STICKY="$OPTARG"
                        ;;
                    udp)
                        readonly TCPSEND=0
                        ;;
                    title)
                        readonly title="$OPTARG"
                        ;;
                    text=*)
                        readonly text="$OPTARG"
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
                readonly REGISTER=1
                ;;
            a)  # Application name
                readonly application="$OPTARG"
                ;; 
            n)  # Notifiction text
                names+=( "$OPTARG" )
                ;;

            H)  # Host & IP
                readonly HOST=${OPTARG%:*}      # strip off : and trailing text
                readonly PORT=${OPTARG#*:}      # strip off leading text to :
                ;;
            P)  # Password
                readonly PASSWORD="$OPTARG"
                ;;
            p)  # Priority
                readonly PRIORITY="$OPTARG"
                ;;
            s)  # Sticky 
                readonly STICKY=1
                ;;
            u)  # UDP
                tcpsend=0
                ;;
            T)  # Title
                readonly title="$OPTARG"
                ;;
            t)  # Message text
                readonly text="$OPTARG"
                ;;
            *)
                if [ "$OPTERR" != 1 ] || [ "${optspec:0:1}" = ":" ]; then
                    echo "Non-option argument: '-${OPTARG}'" >&2
                    usage
                fi
                ;;
        esac
    done
    if [[ $REGISTER -eq 1 ]]; then
        if [[ -z $application || ${#names[@]} -eq 0 ]]; then
            echo "$PROGNAME requires application name and notifications list to register."
            echo
            usage      
        fi
    else
        if [[ -z $application || ${#names[@]} -eq 0 || -z $title ]]; then
            echo "$PROGNAME requires application name and notification to send to Growl."
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
    # 2. A cyptographically secure salt is generated (should be between 4 and 16 bytes)
    # 3. The salt bytes are appended to the password bytes to form the key basis
    # 4. The key is generated by computing the hash of the key basis using one of the supported hashing algorithms
    # 5. The key hash is produced by computing the hash of the key (using the same hashing algorithm used in step 4) and hex-encoding it to a fixed-length string


    # 1. Generate a reasonbly secure salt and trim it to 16 bytes
    local salt=$( date | md5 | base64 )   
    salt=${salt:0:16}    
    local hexsalt=$( printf "%s" "$salt" | xxd -p )
    # 2. Append salt bytes to password bytes to form key basis
    local keybasis="$password$salt"
    # 3. Compute the hash of the key basis 
    local key=$( printf "%s" "$keybasis" | md5 )
    key=${key:0:32}
    # 4. Compute the hash of the key (note key should not be hex encoded at this point, or 
    #    as a work around we use xxd -r).
    local keyhash=$( printf "%s" "$key" | xxd -r -p | md5 )
    # 5. Convert the salt to a hex string.

    echo "MD5:$keyhash.$hexsalt"
}

send_gntp () {
    msg="$1" 
    if [[ $USENC -eq 1 ]] && hash nc 2>/dev/null; then
        IFS=$'\n'
        result=( $(printf "%b" "$msg" | nc -w 1 127.0.0.1 23053 ) )
    else
        exec 10<>/dev/tcp/127.0.0.1/23053
        printf "%b" "$msg"  >&10
        for (( a=0 ; a<=3; a++ )); do
            read -u 10 result[$a]
        done
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

build_register_message () {
    local _keystring="$1"; shift
    local _application="$1"; shift
    local _names=("$@")
    local header
    local body
    
    printf "GNTP/1.0 REGISTER NONE %s\r\n" $_keystring
    printf "Application-Name: %s\r\n" $_application
    printf "Notifications-Count: %s\r\n" ${#_names[@]}

    for i in ${_names[@]}; do
        printf "\r\nNotification-Name: %s\r\n" $i
        printf "Notification-Enabled: True\r\n"
    done
    printf "\r\n\r\n"
}

build_notify_message () {
    local _keystring=$1; shift
    local _application=$1; shift
    local _name=$1; shift
    local _title=$1; shift
    local _text=$1

    printf "GNTP/1.0 NOTIFY NONE %s\r\n" $_keystring
    printf "Application-Name: %s\r\n" $_application
    printf "Notification-Name: %s\r\n" $_name
    printf "Notification-Title: %s\r\n" $_title
    printf "Notification-Text: %s\r\n" $_text
    printf "\r\n\r\n"
}


cmdline $@

if [[ -n $PASSWORD ]]; then
    keystring=$(generate_key $PASSWORD)
else
   keystring="NONE"
fi
if [[ -n $REGISTER ]]; then
    msg_text=$(build_register_message "$keystring" "$application" "${names[@]}")
else
    msg_text=$(build_notify_message "$keystring" \
                                    "$application" \
                                    "${names[0]}" \
                                    "$title" \
                                    "$text" )
fi
send_gntp "$msg_text"




