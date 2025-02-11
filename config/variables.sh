#!/bin/bash

# -------------------------------------------------------------------------------------------------
# Network Configuration: MAC addresses and Predictiable names
#
# Predictible names will be used for the USB Wifi Cards (ID_NET_NAME_MAC)
#  wl = wlan
#  x  = MAC
#  aabbccddffgg = MAC address of device
# -------------------------------------------------------------------------------------------------

# Alfa AC1200 USB Wireless cards
WLAN_INTERFACE_AC1200_1="CHANGE_ME"
WLAN_INTERFACE_AC1200_2="CHANGE_ME"

# MAC Address of built-in Ethernet interface
MAC_ETH0="CHANGE_ME"

# MAC Address of built-in WiFi interface
MAC_WLAN0="CHANGE_ME"

# -------------------------------------------------------------------------------------------------
# Management Access Point
# -------------------------------------------------------------------------------------------------
AP_ESSID="CHANGE_ME"
AP_WPA_PASSPHRASE="CHANGE_ME"
MGMT_INTERFACE="CHANGE_ME"

# -------------------------------------------------------------------------------------------------
# Target directory to install the scanning scripts
# -------------------------------------------------------------------------------------------------
TARGET_DIR="/root/wifi_scanning_tools"

# -------------------------------------------------------------------------------------------------
# Base username
# -------------------------------------------------------------------------------------------------
BASE_USER_NAME="CHANGE_ME"

# -------------------------------------------------------------------------------------------------
# Directories
# -------------------------------------------------------------------------------------------------
REPO_DIR="/home/${BASE_USER_NAME}/repos"
TOOL_DIR="/opt/tools"
DRIVER_DIR="/opt/drivers"

# -------------------------------------------------------------------------------------------------
# Identifies for USB devices (Output from lsusb)
# -------------------------------------------------------------------------------------------------
GPS_UNIT="Prolific Technology, Inc. ATEN Serial Bridge"
TP_LINK="RTL8188EUS 802.11n"
ALFA_AC1200="RTL8812AU"