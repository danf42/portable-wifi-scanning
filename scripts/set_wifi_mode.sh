#!/bin/bash

# Check if we are running script as root
if [[ $(echo $EUID) -ne 0 ]]; then
   echo "${RED}[!] This script must be run as root ${RESET}"
   exit 1
fi

devices=`iw dev | grep Interface | sed -e 's/^[[:space:]]*//' | cut -d" " -f2`

echo "List of Wifi Devices and current mode:"
for device in $devices; do
	
	mode_type=`iw $device info | grep type | sed -e 's/^[[:space:]]*//' | cut -d" " -f2`  
	echo " $device : $mode_type"

done

read -p "Select device to use: " device

mode_type=`iw $device info | grep type | sed -e 's/^[[:space:]]*//' | cut -d" " -f2`  

if [[ "managed" == ${mode_type} ]]; then

   ip link set ${device} down
   iw ${device} set monitor control
   ip link set ${device} up

else

   ip link set ${device} down
   iw ${device} set type managed 
   ip link set ${device} up

fi

iw $device info

