#!/bin/bash

# get commandline arguments
if [[ $# -ne 1 ]]; then
    echo "${RED}[!] Missing number of arguments ${RESET}"
    echo "${RED}[!] run_hcxdump.sh [start|stop|restart] ${RESET}"
    exit 1
fi

# Source configuration file 
source VARIABLE_PATH

# set terminal output colors
RED=`tput setaf 1`
GREEN=`tput setaf 2`
BLUE=`tput setaf 4`
YELLOW=`tput setaf 3`
RESET=`tput sgr0`

# tmux session name
SESSION="wifi-hcxdump"

# Check if we are running script as root
if [[ $EUID -ne 0 ]]; then
   echo "${RED}[!] This script must be run as root ${RESET}" 
   exit 1
fi

# -------------------------------------------------------------------------------------------------
# Verify all required USB devices are connected and found
# -------------------------------------------------------------------------------------------------
verify_usb_devices(){
  echo "${YELLOW}[~] Verify necessary USB devices are attached...${RESET}"

  GPS_UNIT="Prolific Technology, Inc. PL2303 Serial Port"
  TP_LINK="RTL8188EUS 802.11n"
  ALFA_AC1200="RTL8812AU"

  lsusb_results=$(lsusb)

  count=$(echo ${lsusb_results} | grep -c "${GPS_UNIT}")

  if [[ ${count} -ne 1 ]]; then
          echo "${RED}[!] Missing GPS Receiver ${RESET}"
          return 1
  fi

  count=$(echo ${lsusb_results} | grep -c "${TP_LINK}")

  if [[ ${count} -ne 1 ]]; then
          echo "${RED}[!] Missing TP-LINK Wifi Adapter ${RESET}"
          return 1
  fi

  count=$(echo ${lsusb_results} | grep -c "${ALFA_AC1200}")

  if [[ ${count} -ne 1 ]]; then
          echo "${RED}[!] Missing ALFA AC1200 Wifi adapters ${RESET}"
          return 1
  fi

  echo "${GREEN}[*] All required usb devices found!  ${RESET}"
  lsusb
  return 0

}

# -------------------------------------------------------------------------------------------------
# Determine ALFA1200 card plugged into device
# -------------------------------------------------------------------------------------------------
get_alfa1200_card(){

  airmonng_results=$(airmon-ng)

  count=$(echo ${airmonng_results} | grep -c ${WLAN_INTERFACE_AC1200_1} )

  if [[ ${count} -eq 1 ]]; then
     WLAN_INTERFACE_AC1200=${WLAN_INTERFACE_AC1200_1}
  else 
     WLAN_INTERFACE_AC1200=${WLAN_INTERFACE_AC1200_2}
  fi

  echo ${WLAN_INTERFACE_AC1200}
}

# -------------------------------------------------------------------------------------------------
# Wait for time to be synced
# -------------------------------------------------------------------------------------------------
time_sync(){

    echo "${YELLOW}[*] Wait for time to sync ${RESET}"

    i=0

    while [ $i -lt 5 ]; do
        status=$(ntpq -p | grep -c "*")

        if [ $status -eq 1 ]; then
            echo "${GREEN}[*] Time successfully synced!  ${RESET}"

            ntpq -p
            echo
            break
        fi

        echo "${RED}[!] Time has not synced yet  ${RESET}"

        # Force time to sync with GPS
        ntpdate -s 127.127.28.0

        i=$[$i+1]
        sleep 5
        
    done

}

# -------------------------------------------------------------------------------------------------
# Start tmux session and hcxdump
# -------------------------------------------------------------------------------------------------
start(){

    echo "${BLUE}[*] Starting hcxdump ${RESET}"

    verify_usb_devices || exit 1

    # Wait for time to be synced
    time_sync
    timedatectl

    # Get the date
    now=`date +"%Y-%m-%d"`

    # stop networking processes that will interfer with airodump
    airmon-ng check kill
    sleep 5

    # Determine which ALFA AC1200 card has been plugged in
    WLAN_INTERFACE_AC1200=$(get_alfa1200_card)

    # put the ALFA cards into monitor mode
    echo "${YELLOW}[~] Start ${WLAN_INTERFACE_AC1200} in monitor mode ${RESET}"
    airmon-ng start ${WLAN_INTERFACE_AC1200}

    # Verify cards are in monitor mode
    count=`iwconfig ${WLAN_INTERFACE_AC1200} | grep -c 'Mode:Monitor'`

    if [[ $count -ne 1 ]]; then
        echo "${RED}[!] ${WLAN_INTERFACE_AC1200} is not in monitor mode ${RESET}"
        exit 1
    fi     

    echo "${YELLOW}[~] Start hcxdump on interfaces ${WLAN_INTERFACE_AC1200} ${RESET}"

    output_dir="/root/${now}"
    # Create directory to store data
    if [[ ! -d ${output_dir} ]]; then 
        mkdir ${output_dir}
    fi

    # save the current directory
    prev_dir=`pwd`

    # change directory to store our data
    cd ${output_dir}

    # check if session already exists
    session_exists=`tmux list-sessions | grep ${SESSION}`

    if [[ -z "$session_exists" ]] ; then

        # start a new session with the name
        tmux new-session -d -s ${SESSION}

        # name the first window and clear it
        tmux rename-window -t 0 'Main'
        tmux send-keys -t 'Main' 'clear' C-m

        # create window for airodump
        tmux new-window -t ${SESSION}:1 -n 'hcxdump'

        # send the airodump commands to the correct session/window/panel
        tmux send-keys -t ${SESSION}:'hcxdump' "hcxdumptool -o ${now}_hcxdump.pcapng -i ${WLAN_INTERFACE_AC1200} --enable_status 1 --disable_client_attacks --disable_deauthentication --use_gpsd" C-m 

        # create another window to monitor gps
        tmux new-window -t ${SESSION}:2 -n 'gps'
        tmux send-keys -t ${SESSION}:2 'clear' C-m
        tmux send-keys -t ${SESSION}:2 'gpsmon' C-m

        # make window the active window
        tmux select-window -t ${SESSION}:'hcxdump'
    fi

    tmux list-sessions
}

# stop tmux session
stop(){

  # Determine which ALFA AC1200 card has been plugged in
  WLAN_INTERFACE_AC1200=$(get_alfa1200_card)

  # check if session already exists
  session_exists=`tmux list-sessions | grep ${SESSION}`

  if [[ ! -z  "$session_exists" ]] ; then

      # stop the airodump collection
      tmux send-keys -t ${SESSION}:'hcxdump' C-c

      # kill the tmux session
      tmux kill-session -t ${SESSION}
  fi
    
  sleep 5

  # put the ALFA cards into managed mode
  echo "${YELLOW}[~] Start ${WLAN_INTERFACE_AC1200} in managed mode ${RESET}"
  airmon-ng stop ${WLAN_INTERFACE_AC1200}

  # Bring the primary interface back up
  interface=$(ip addr show | grep -E 'wlan0|eth0' | awk '/inet.*brd/{print $NF; exit}')
  
  echo "${YELLOW}[~] Attempting to bring up ${interface}  ${RESET}"

  if [[ "${interface}" = "wlan0" || "${interface}" = "eth0" ]] ; then
    ifdown ${interface}
    ifup ${interface}
  fi

}

# -------------------------------------------------------------------------------------------------
# Start/Stop/Restart script
# -------------------------------------------------------------------------------------------------
case "$1" in
  start)
  echo "${BLUE}[*] Start hcxdump ${RESET}"
    start
  ;;
  
  stop)
    echo "${BLUE}[*] Stop hcxdump ${RESET}"
    stop
  ;;

  restart)
    echo "${BLUE}[*] Restart hcxdump ${RESET}"
    stop
    start
  ;;

  *)
    echo "${RED}[!]  run_hcxdump.sh [start|stop|restart] ${RESET}"
    exit 1
    ;;
esac
