#!/bin/bash
#set -x

INPUT=$1
MAINTEMP="/tmp/nfparsetmp"

intexit() {
    # Allows clean exit via Ctrl-C
    kill -HUP -$$
}

hupexit() {
    # Allows clean exit via Ctrl-C
    echo
    echo "Interrupted"
    echo
    exit
}

show_spinner()
{
    # Simple loading progress indicator, waits for the above process to end.
    #
    # Usage:
    # command &
    # show_spinner "$!"

    local -r pid="${1}"
    local -r delay='0.2'
    local spinstr='\|/-'
    local temp
    printf "Loading"

    while ps a | awk '{print $1}' | grep -q "${pid}"; do
        temp="${spinstr#?}"
        printf " [%c]  " "${spinstr}"
        spinstr=${temp}${spinstr%"${temp}"}
        sleep "${delay}"
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
    printf '\n'
}

list_set_rot(){
    # Determines whether to use -r or -R while using nfdump
    # Only takes $INPUT

    if [[ $INPUT == *":"* ]] || [[ -d $INPUT ]]; then
        option='-R'
        echo $option
    elif [[ -f $INPUT ]]; then
        option='-r'
        echo $option
    else
        echo "Error, unknown input."
        exit 0
    fi
}

list_set(){
    # Sets/gets the list for a given type and saves the output to a temporary folder.
    # Usage:
    # list_set "$TYPE" "$COUNT"
    # list_set spa 100

    TYPE=$1
    COUNT=$2
    STARTTIME=$(date +%s)
    option=$(list_set_rot $INPUT)
    case $TYPE in
        spa )
            typeopts="-o extended -A srcport -O flows -n $COUNT"
            TEMP="${MAINTEMP}/list_spa_${COUNT}"
            ;;

        dpa )
            typeopts="-o extended -A dstport -O flows -n $COUNT"
            TEMP="${MAINTEMP}/list_dpa_${COUNT}"
            ;;

        sia )
            typeopts="-o extended -A srcip -O flows -n $COUNT"
            TEMP="${MAINTEMP}/list_sia_${COUNT}"
            ;;

        dia )
            typeopts="-o extended -A dstip -O flows -n $COUNT"
            TEMP="${MAINTEMP}/list_dia_${COUNT}"
            ;;

        std )
            typeopts="-o extended -a -O flows -n $COUNT"
            TEMP="${MAINTEMP}/list_std_${COUNT}"
            ;;

        stbps )
            typeopts="-o extended -s record/bps -a -n $COUNT"
            TEMP="${MAINTEMP}/list_stbps_${COUNT}"
            ;;

        dbps )
            typeopts="-o extended -s record/bps -A dstip -n $COUNT"
            TEMP="${MAINTEMP}/list_dbps_${COUNT}"
            ;;

        sbps )
            typeopts="-o extended -s record/bps -A srcip -n $COUNT"
            TEMP="${MAINTEMP}/list_sbps_${COUNT}"
            ;;

        stbyt )
            typeopts="-o extended -s record/bytes -a -n $COUNT"
            TEMP="${MAINTEMP}/list_stbyt_${COUNT}"
            ;;

        dbyt )
            typeopts="-o extended -s record/bytes -A dstip -n $COUNT"
            TEMP="${MAINTEMP}/list_dbyt_${COUNT}"
            ;;

        sbyt )
            typeopts="-o extended -s record/bytes -A srcip -n $COUNT"
            TEMP="${MAINTEMP}/list_sbyt_${COUNT}"
            ;;

        sidpa )
            typeopts="-o extended -A dstport,srcip -O flows -n $COUNT"
            TEMP="${MAINTEMP}/list_sidpa_${COUNT}"
            ;;

        didpa )
            typeopts="-o extended -A dstport,dstip -O flows -n $COUNT"
            TEMP="${MAINTEMP}/list_didpa_${COUNT}"
            ;;

        CUSTOM )
            # Takes custom instead of list type. Allows typeopts to be given dynamically.
            CPARAMS="$2"
            typeopts="$CPARAMS"
            filext=$(echo ${CPARAMS// /_})
            TEMP="${MAINTEMP}/list_${filext}"
            ;;
    esac
    nfdump $option $INPUT $typeopts > $TEMP
    used_command="nfdump $option $INPUT $typeopts"
    echo
    cat $TEMP | tee ${MAINTEMP}/last_list
    ENDTIME=$(date +%s)
    echo "Time to complete: $(( ENDTIME - STARTTIME )) seconds." | tee -a $TEMP
    echo "Command: $used_command" | tee -a $TEMP
}

ask_count(){
    # Asks fo the $COUNT parameter for list_get/list_set. Sets to default value if none given.
    # Usage:
    # ask_count "$DEFAULT"
    # ask_count 30

    DEFAULT=$1
    read -p "List item count [${DEFAULT}]: " COUNT
    if [[ -z $COUNT ]]; then
        COUNT=$DEFAULT
        echo $COUNT
    else
        echo $COUNT
    fi
}

list_to_ip(){
    # Converts the last_list file to an all IP format for whois querying. Determines if the SRC or DST fileds contains valid IP addresses.
    # Usage:
    # list_to_ip "$FILE" where file is of nfdump out format.

    FILE=$1
    SRC=$(cat "$FILE" | grep -vi ^[a-z] | sed -n 3p | awk -F' ' '{print $5}' | awk -F':' '{print $1}')
    DST=$(cat "$FILE" | grep -vi ^[a-z] | sed -n 3p | awk -F' ' '{print $7}' | awk -F':' '{print $1}')
    if [[ $SRC =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && [[ $SRC != '0.0.0.0' ]] && [[ $DST =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && [[ $DST != '0.0.0.0' ]]; then
        IPLIST=$(cat "$FILE" | grep -vi ^[a-z] | awk -F' ' '{print $5,7}' | awk -F':' '{print $1}' | awk '($1+0)>0 && ($1+0)<=255')
        echo "" > ${MAINTEMP}/last_ip
    elif [[ $SRC =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && [[ $SRC != '0.0.0.0' ]]; then
        IPLIST=$(cat "$FILE" | grep -vi ^[a-z] | awk -F' ' '{print $5}' | awk -F':' '{print $1}' | awk '($1+0)>0 && ($1+0)<=255')
        echo "$IPLIST" > ${MAINTEMP}/last_ip
    elif [[ $DST =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && [[ $DST != '0.0.0.0' ]]; then
        IPLIST=$(cat "$FILE" | grep -vi ^[a-z] | awk -F' ' '{print $7}' | awk -F':' '{print $1}' | awk '($1+0)>0 && ($1+0)<=255')
        echo "$IPLIST" > ${MAINTEMP}/last_ip
    else
        rm -f ${MAINTEMP}/last_ip
    fi
}

list_get(){
    # Checks if the list being queried already exists and if it does, returns that one. If it doesn't, calls list_set. Always used insted of list_set.
    # Also determines if the CUSTOM parameter will be applied and allows user input accordingly.
    # list_to_ip conversation is handled by this function.
    # Usage:
    # list_get "$TYPE" "$COUNT"
    # list_get sia 100

    PARAM=$1
    COUNT=$2
    TYPE=""
    TEMP="${MAINTEMP}"

    if [[ $PARAM == "CUSTOM" ]]; then
        TYPE="CUSTOM"
    fi

    if [[ $TYPE == "CUSTOM" ]]; then
        echo "Example: -o extended -a -n 20 (q to quit)"
        read -p "Provide options: " CPARAMS
        if [[ $CPARAMS == "q" ]]; then
            menu
        fi
        filext=$(echo ${CPARAMS// /_})
        FILE="${TEMP}/list_${filext}"
    else
        FILE="${TEMP}/list_${PARAM}_${COUNT}"
    fi
    if [[ -f "$FILE" ]]; then
        cat "$FILE" | tee ${MAINTEMP}/last_list
    else
        if [[ $TYPE == "CUSTOM" ]]; then
            list_set CUSTOM "$CPARAMS"
        else
            list_set $PARAM $COUNT
        fi
    fi

    list_to_ip $FILE

    for f in ${MAINTEMP}/wll*; do
        [ -e "$f" ] && rm -f ${MAINTEMP}/wll*
    done
    if [[ $PARAM == "CUSTOM" ]]; then
        touch "${MAINTEMP}/wll_${filext}"
    else
        touch "${MAINTEMP}/wll_${PARAM}_${COUNT}"
    fi
    printf '\n'
    date_interval
    printf '\n'
}

list_last(){
    # Simply provides the result of the last nfdump query.
    # Usage:
    # list_last

    printf '\n'
    cat ${MAINTEMP}/last_list | grep -vi ^[a-z]
}

#ipinfo_set(){
    # Stored here in case the other WHOIS method fails for some reason. Obsolete for now.
    # Sets the WHOIS info for a given IP address and greps for given parameters, saves the result to a temporary folder.
    # Usage:
    # ipinfo_set "$IP"
    # ipinfo_set "94.103.32.130"

    #IP=$1
    #TEMP="${MAINTEMP}/whois/${IP}"
    #if [[ ! -d "${MAINTEMP}/whois" ]]; then
        #mkdir "${MAINTEMP}/whois"
    #fi
    #whois $IP > $TEMP

    #origin=$(grep "origin:" $TEMP | awk -F'[[:space:]][[:space:]]+' '{print $2}')
    #orgname=$(grep "org-name:" $TEMP | awk -F'[[:space:]][[:space:]]+' '{print $2}')
    #role=$(grep "role:" $TEMP | awk -F'[[:space:]][[:space:]]+' '{print $2}')
    #abuse=$(grep "abuse-mailbox:" $TEMP | awk -F'[[:space:]][[:space:]]+' '{print $2}')
    #netname=$(grep "netname:" $TEMP | awk -F'[[:space:]][[:space:]]+' '{print $2}')
    #descr=$(awk '/descr:/{i++}i==2' $TEMP | grep descr | awk -F'[[:space:]][[:space:]]+' '{print $2}')
    #printf "$origin : $orgname : $descr : $role : $abuse : $netname"

#}

#ipinfo_get(){
    # Determines if a temporary file for the current query already exists. If yes, provides it, if not, calls ipinfo_set to set it.
    # Usage:
    # ipinfo_get "94.103.32.130"

    #IP=$1
    #TEMP="${MAINTEMP}/whois/${IP}"
    #if [[ -f "$TEMP" ]]; then
        #cat "$TEMP"
    #else
        #ipinfo $IP
    #fi
#}

whois_query_set(){
    # Queries whois.cymru.com for bulk IP addresses. Outputs the results in a nice, readable format. Very fast. Saves the result in the related temporary file.
    # $TEMP: The temporary file which is suitable for querying whois.cymru.com servers.
    # $IPLIST: All IP list provided by list_to_ip
    # $TYPE: Takes either "ADDRESS" or "BLOCK". BLOCK only queries for the IP/SUBNET ranges. ADDRESS queries for all addresses in the list.
    # Usage:
    # whois_query_set "$TEMP" "$IPLIST" "$TYPE"
    # whois_query_set "/tmp/file" "/tmp/ip_list" "ADDRESS"

    TEMP=$1
    IPLIST=$2
    TYPE=$3
    if [[ ! -d "${MAINTEMP}/whois" ]]; then
        mkdir "${MAINTEMP}/whois"
    fi
    echo begin > $TEMP
    echo prefix >> $TEMP
    echo countrycode >> $TEMP
    echo "$IPLIST" >> $TEMP
    echo end >> $TEMP
    if [[ $TYPE == "BLOCK" ]]; then
        ncat whois.cymru.com 43 < $TEMP | tail -n +2 | sort -b -u -t'|' -k3 | awk '!($2="")' | awk '!($2="")' > ${TEMP}_processed
    elif [[ $TYPE == "ADDRESS" ]]; then
        ncat whois.cymru.com 43 < $TEMP | tail -n +2 > ${TEMP}_processed
    fi
    cat ${TEMP}_processed | tee ${MAINTEMP}/whois/last
}

whois_query_get(){
    # Determines if a temporary file for the current query exists. If yes, provides it, if not, calls whois_query_set. Always used instead of whois_query_set.
    # $TEMP: The temporary file which is suitable for querying whois.cymru.com servers.
    # $IPLIST: All IP list provided by list_to_ip
    # $TYPE: Takes either "ADDRESS" or "BLOCK". BLOCK only queries for the IP/SUBNET ranges. ADDRESS queries for all addresses in the list.
    # Usage:
    # whois_query_get "$TEMP" "$IPLIST" "$TYPE"
    # whois_query_get "/tmp/file" "/tmp/ip_list" "ADDRESS"

    TEMP=$1
    IPLIST=$2
    TYPE=$3
    if [[ -f "$TEMP" ]]; then
        printf '\n'
        cat "$TEMP" | tee ${MAINTEMP}/whois/last
    else
        whois_query_set $TEMP "$IPLIST" $TYPE
    fi
}

whois_search(){
    # Silently gets the "Source IP Aggregated" list for $COUNT items. Sets the appropriate temporary files, and case insensitively greps the WHOIS results of the said list.
    # Usage:
    # whois_search "$WORD" "$COUNT"
    # whois_search "VeriTeknik" "100"

    WORD=$1
    COUNT=$2
    list_get sia $COUNT &> /dev/null
    IPLIST=$(cat ${MAINTEMP}/last_ip)
    whois_query_get "${MAINTEMP}/whois/sia_${COUNT}" "$IPLIST" ADDRESS &> /dev/null
    LIST="${MAINTEMP}/whois/sia_${COUNT}_processed"
    RESULT=$(printf '\n' && grep -i "$WORD" "$LIST")
    entrap "$RESULT"
}

block_owner_set(){
    # Sets the IP block owner information via WHOIS querying. Forms the appropriate temporary files. Uses list_get sia 100 to determine incoming connections.
    # Usage:
    # block_owner_set "$BLOCK"
    # block_owner_set "94.103"

    block=$1
    TEMP="${MAINTEMP}/whois/${block}"
    list=$(list_get sia 100)
    block_ips=$(echo "$list" | grep -vi ^[a-z] | awk -F' ' '{print $5}' | awk -F':' '{print $1}' | awk '($1+0)>0 && ($1+0)<=255' | grep "^${block}")
    printf '\n'
    whois_query_get $TEMP "$block_ips" BLOCK
}

block_owner_get(){
    # Determines if the queried result already exists. If yes, provides it while also copying it to /whois/last. If not, calls block_owner_set. Always used instead of block_owner_set.
    # Usage:
    # block_owner_get "$BLOCK"
    # block_owner_set "94.103"

    block=$1
    TEMP="${MAINTEMP}/whois/${block}_processed"
    if [[ -f "$TEMP" ]]; then
        printf '\n'
        cat "$TEMP" | tee ${MAINTEMP}/whois/last
    else
        block_owner_set "$block"
    fi
}

ip_owner_set(){
    # Sets the WHOIS information for a single IP address. Puts the result to appropriate temporary file.
    # Usage:
    # ip_owner_set "$IP"
    # ip_owner_set "94.103.32.130"

    IP=$1
    TEMP="${MAINTEMP}/whois/${IP}"
    whois_query_get $TEMP "$IP" ADDRESS
}

ip_owner_get(){
    # Determined of the queried result already exists. If yes, provides it, if not, calls ip_owner_set. Alwas used instead of block_owner_set.
    # Usage:
    # block_owner_get "$BLOCK"
    # block_owner_get "94.103.32.130"

    IP=$1
    TEMP="${MAINTEMP}/whois/${IP}"
    if [[ -f "$TEMP" ]]; then
        printf '\n'
        cat "$TEMP"
    else
        ip_owner_set $TEMP "$IP"
    fi
}

whois_last(){
    # Simply calls the result of the last WHOIS query.
    # Usage:
    # whois_last

    printf '\n'
    cat ${MAINTEMP}/whois/last
}

date_interval(){
    # Gets the time interval for the current $INPUT. If input is current, acts accordingly. Prints in pretty format.
    # Usage:
    # date_interval

    if [[ $INPUT == *":"* ]] || [[ -d $INPUT ]]; then
        file1=$(echo $INPUT | awk -F':' '{print $1}')
        date1_unf=$(echo $file1 | awk -F'.' '{print $2}')
        date1=$(echo $date1_unf | sed -r 's/^.{4}/&-/;:a; s/([-:])(..)\B/\1\2:/;ta;s/:/-/;s/:/ /')
        file2=$(echo $INPUT | awk -F':' '{print $2}')
        date2=$(stat -c %Y "$file2" | awk '{print strftime("%F %H:%M", $1)}')
        printf "From: $date1\nTo: $date2\n" | column -t
    elif [[ -f $INPUT ]]; then
        date2=$(stat -c %Y "$INPUT" | awk '{print strftime("%F %H:%M", $1)}')
        date1_unf=$(echo $INPUT | awk -F'.' '{print $2}')
        if [[ $date1_unf == 'current' ]]; then
            date1=$(echo $date2 | awk '{split($2, a, ":"); printf "%s %s:%02d", $1, a[1],int(a[2]/5)*5}')
        else
            date1=$(echo $date1_unf | sed -r 's/^.{4}/&-/;:a; s/([-:])(..)\B/\1\2:/;ta;s/:/-/;s/:/ /')
        fi
        printf "From: $date1\nTo: $date2\n" | column -t
    fi
}

top_blocks(){
    # Counts the number of occurences of XXX.YYY format IP blocks. Gets the top $COUNT results. Uses list_get sia 100 to get source IP addresses. Then asks the user if he/she wants to see the owners of those blocks.
    # Usage:
    # top_blocks "$COUNT"
    # top_blocks 10
    STARTTIME=$(date +%s)
    COUNT=$1
    list=$(list_get sia 100)
    top_offending_blocks=$(echo "$list" | grep -vi ^[a-z] | awk -F' ' '{print $5}' | awk -vOFS='.' -F'.' '{print $1,$2}' | awk '($1+0)>0 && ($1+0)<=255' | sort -n | uniq -c | sort -nr | head -n $COUNT)
    date_interval
    echo
    printf "$top_offending_blocks\n"| nl -w 2 | column -t
    ENDTIME=$(date +%s)
    echo "Time to complete: $(( ENDTIME - STARTTIME )) seconds."
    echo

    tob_list=($(echo "$top_offending_blocks" | awk -F' ' '{print $2}'))
    select ipsel in "${tob_list[@]}"; do
        case "$ipsel" in
            "" )
                menu
                break
                ;;

            * )
                title "Result"
                result=$(block_owner_get "$ipsel")
                entrap "$result"
                echo
                top_blocks $COUNT
                break
                ;;
        esac
    done
}

entrap(){
    # Provides a pretty line with the length of the item that will be delimited by it. Might require an additional printf '\n' before the actual item depending on the input.
    # Usage:
    # entrap "$CAGE"
    # entrap $(printf '\n' && echo "$INPUT")

    CAGE=$1
    MAX_WIDTH=$(echo "$CAGE" | awk '{print length, $0}' | sort -nr | head -1)
    REP_COUNT=$(( ${#MAX_WIDTH} / 2 ))
    repeat '+-' $REP_COUNT
    echo "$CAGE"
    repeat '+-' $REP_COUNT
    printf '\n'

}

top_consumers(){
    # To be implemented.
    echo Unimplemented
    #inbound outbound
}

quick_lists(){
    # A quick list of nfdump presets that are thought to be of most use.
    # Usage:
    # quick_lists

    DEFAULT_COUNT=30
    title "Quick Lists"
    printf '\n'
    select choices in "Source Port Aggregated" "Destination Port Aggregated" "Source IP Aggregated" "Destination IP Aggregated" "Source bps Aggregated" "Destination bps Aggregated" "Source Bytes Aggregated" "Destination Bytes Aggregated" "Source IP to Destination Port Aggregated" "Destination IP - Destination Port Aggregated" "Filter Last List" "WHOIS Last List" "Filter Last WHOIS" "Reinitialize" "Back"; do
        case $choices in
            "Source Port Aggregated" )
                title "Source Port Aggregated"
                COUNT=$(ask_count $DEFAULT_COUNT)
                list_get spa $COUNT &
                show_spinner "$!"
                quick_lists
                break;;

            "Destination Port Aggregated" )
                title "Destination Port Aggregated"
                COUNT=$(ask_count $DEFAULT_COUNT)
                list_get dpa $COUNT &
                show_spinner "$!"
                quick_lists
                break
                ;;

            "Source IP Aggregated" )
                title "Source IP Aggregated"
                COUNT=$(ask_count $DEFAULT_COUNT)
                list_get sia $COUNT &
                show_spinner "$!"
                quick_lists
                break
                ;;

            "Destination IP Aggregated" )
                title "Destination IP Aggregated"
                COUNT=$(ask_count $DEFAULT_COUNT)
                list_get dia $COUNT &
                show_spinner "$!"
                quick_lists
                break
                ;;

            "Source bps Aggregated" )
                title "Source bps Aggregated"
                COUNT=$(ask_count $DEFAULT_COUNT)
                list_get sbps $COUNT &
                show_spinner "$!"
                quick_lists
                break
                ;;

            "Destination bps Aggregated" )
                title "Destination bps Aggregated"
                COUNT=$(ask_count $DEFAULT_COUNT)
                list_get dbps $COUNT &
                show_spinner "$!"
                quick_lists
                break
                ;;

            "Source Bytes Aggregated" )
                title "Source Bytes Aggregated"
                COUNT=$(ask_count $DEFAULT_COUNT)
                list_get sbyt $COUNT &
                show_spinner "$!"
                quick_lists
                break
                ;;

            "Destination Bytes Aggregated" )
                title "Destination Bytes Aggregated"
                COUNT=$(ask_count $DEFAULT_COUNT)
                list_get dbyt $COUNT &
                show_spinner "$!"
                quick_lists
                break
                ;;

            "Source IP to Destination Port Aggregated" )
                title "Source IP to Destination Port Aggregated"
                COUNT=$(ask_count $DEFAULT_COUNT)
                list_get sidpa $COUNT &
                show_spinner "$!"
                quick_lists
                break
                ;;

            "Destination IP - Destination Port Aggregated" )
                title "Destination IP to Destination Port Aggregated"
                COUNT=$(ask_count $DEFAULT_COUNT)
                list_get didpa $COUNT &
                show_spinner "$!"
                quick_lists
                break
                ;;

            "Filter Last List" )
                # greps the last nfdump query result. Also accepts input like -v '94.103'
                title "Filter Last List"
                FLLLIST=$(list_last)
                FLLRESULT=$(list_grep "$FLLLIST" "quick_lists")
                echo "$FLLRESULT" > ${MAINTEMP}/last_list
                list_to_ip ${MAINTEMP}/last_list
                printf '\n'
                entrap "$FLLRESULT"
                printf '\n'
                quick_lists
                break
                ;;

            "WHOIS Last List" )
                # Queries the last nfdump query for WHOIS results.
                WLLTEMP=$(find ${MAINTEMP} -printf "%f\n" | grep wll* )
                WLLTYPE=$(echo $WLLTEMP | awk -F'_' '{print $2}')
                WLLCOUNT=$(echo $WLLTEMP | awk -F'_' '{print $3}')
                WLLWTEMP="${MAINTEMP}/whois/${WLLTYPE}_${WLLCOUNT}"
                WLLWIPLIST=$(cat ${MAINTEMP}/last_ip)
                echo
                title "WHOIS Last List"
                if [[ -f "${MAINTEMP}/last_ip" ]]; then
                    WLLRESULT=$(printf '\n' && whois_query_get "$WLLWTEMP" "$WLLWIPLIST" ADDRESS)
                    entrap "$WLLRESULT"
                else
                    printf "List has no IP addresses.\n\n"
                fi
                quick_lists
                break
                ;;

            "Filter Last WHOIS" )
                # greps the last WHOIS query result. Also accepts input like -v 'VeriTeknik'
                title "Filter Last WHOIS"
                FLWLIST=$(whois_last)
                echo "Example: VeriTeknik"
                FLWRESULT=$(list_grep "$FLWLIST" "quick_lists")
                echo "$FLWRESULT" > ${MAINTEMP}/whois/last
                printf "\n"
                entrap "$FLWRESULT"
                printf '\n'
                quick_lists
                break
                ;;

            "Reinitialize" )
                initialize
                quick_lists
                break
                ;;

            "Back" )
                menu
                break
                ;;

            "" )
                menu
                break
                ;;
        esac
    done
}

repeat(){
    # Repeats a string $num times.
    # Usage:
    # repeat "$str" "$num"
    # repeat "Ha" 10

    str=$1
    num=$2
    printf "%0.s${str}" $(seq 1 $num)
}

list_grep(){
    # greps the given input in an interactive manner. Trickery induced to allow grep take additional options like -v
    # Send the user to the provided upper level if input is 'q'.
    # Takes list to be searched and upper menu for arguements.
    # Usage:
    # list_grep "$SEARCH" "$UP"
    # list_grep "$LIST_OF_WHOIS_QUERIES" "$UPPER_MENU"

    SEARCH=$1
    UP=$2
    read -p "grep by (q to quit): " TERM
    TERM1=$(echo "$TERM" | awk -F' ' '{print$1}')
    TERM2=$(echo "$TERM" | awk -F' ' '{print$2}')
    if [[ "$TERM" == "q" ]]; then
        "$UP"
    elif [[ "$TERM1" == "-"* ]]; then
        RESULT=$(printf '\n' && echo "$SEARCH" | eval grep "$TERM1" "$TERM2")
    else
        RESULT=$(printf '\n' && echo "$SEARCH" | grep -i "$TERM")
    fi
    echo "$RESULT"
}


title(){
    # Pretty prints the given string with preset but adjustable borders.
    # Default output for "$STRING" is:

    # +--------------------+
    # |    nfparse v0.1    |
    # +--------------------+

    # Additional parameters can be added to override default from structure.

    # $DASH = Top and bottom elements => Default value = -
    # $SIDE = Left and right elements => Default value = |
    # $CORNER = Corner elements => Default value = +

    # If only $DASH is set, automatically sets $SIDE and $CORNER to value of $DASH.

    # Usage:
    # title "$STRING" "$DASH" "$SIDE" "$CORNER"
    # title "nfparse v0.1"
    # title "nfparse v0.1" '#'
    # title "nfparse v0.1" '#' '||' 'X'

    OFFSET=5
    NAME=$1
    DASH=$2
    SIDE=$3
    CORNER=$4

    if [[ -z $2 ]]; then
        DASH='-'
    fi

    if [[ -z $3 ]] && [[ -z $2 ]]; then
        SIDE='|'
    elif [[ -z $3 ]] && [[ ! -z $2 ]]; then
        SIDE=$(echo $DASH)
    fi

    if [[ -z $4 ]] && [[ -z $2 ]]; then
        CORNER='+'
    elif [[ -z $4 ]] && [[ ! -z $2 ]]; then
        CORNER=$(echo $DASH)
    fi

    CHARS=${#NAME}
    CHARSC=$(( CHARS - 2 ))
    WIDTH=$(( CHARSC + OFFSET * 2 ))

    printf $CORNER
    repeat $DASH $WIDTH
    printf $CORNER
    printf '\n'
    printf $SIDE
    repeat ' ' $(( OFFSET - 1 ))
    printf "$NAME"
    repeat ' ' $(( OFFSET - 1 ))
    printf $SIDE
    printf '\n'
    printf $CORNER
    repeat $DASH $WIDTH
    printf $CORNER
    printf '\n'
    echo
}

banner(){
    # Provides the program start/end banners using title()
    # Usage:
    # banner

    switch=$1
    if [[ "$switch" == "start" ]]; then
        echo
        title "MENU" '-' '|' '+'
        echo
    elif [[ "$switch" == "end" ]]; then
        echo
        title "DONE" '-' '|' '+'
        echo
    fi
}

initialize(){
    # Initializes the script. Checks if the temporary directory exists and rm's it if it is and recreates them. Also prints the date interval of $INPUT.
    # Usage:
    # initialize

    echo 'Initializing...'
    echo
    if [[ -d "${MAINTEMP}" ]]; then
        rm -rf ${MAINTEMP}
    fi
    mkdir ${MAINTEMP}
    printf '\n'
    date_interval
}

menu(){
    # Provides the main menu of the script.
    # Usage:
    # menu

    echo
    banner start
    COUNT=20
    select choices in "Default List" "Quick Lists" "Custom Lists" "Top Consumers" "Most Occurence in Top Flow" "Search IP Owners" "Reinitialize" "Quit"; do
        case $choices in
            "Default List" )
                echo
                title "Default List"
                list_get std $COUNT &
                show_spinner "$!"
                menu
                break
                ;;

            "Quick Lists" )
                echo
                quick_lists
                menu
                break
                ;;

            "Custom Lists" )
                echo
                title "Custom Lists"
                list_get CUSTOM
                menu
                break
                ;;

            "Top Consumers" )
                echo
                title "Top Consumers"
                top_consumers
                menu
                break
                ;;

            "Most Occurence in Top Flow" )
                echo
                title "Most Occurence in Top Flow"
                top_blocks 10
                menu
                break
                ;;

            "Search IP Owners" )
                # Searches the owners of incoming connection IP addresses via WHOIS lookup greps.
                # Uses a list length of 100 by default.
                title "Search IP Owners"
                read -p "Top [X] by flow [100]: (q to quit)" SIOX
                if [[ -z $SIOX ]]; then
                    SIOX=100
                elif [[ $SIOX == "q" ]]; then
                    menu
                fi
                echo "Example: VeriTeknik (q to quit)"
                read -p "Search term: " SIOSEARCH
                if [[ $SIOSEARCH == "q" ]]; then
                    menu
                fi
                whois_search "$SIOSEARCH" $SIOX
                menu
                break
                ;;

            "Reinitialize" )
                echo
                initialize
                menu
                break
                ;;

            "Quit" )
                # Removes temporary directories on exit.
                rm -rf ${MAINTEMP}
                banner end
                exit 0
                break
                ;;

        esac
    done
}

main(){
    # The main function. All are called from here.
    trap hupexit HUP
    trap intexit INT

    echo
    title "nfparse v0.1"
    initialize
    menu
}

main $@
