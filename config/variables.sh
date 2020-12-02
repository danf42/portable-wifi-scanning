#!/bin/bash

# -------------------------------------------------------------------------------------------------
# Network Configuration: MAC addresses and Predictiable names
#
# Predictible names will be used for the USB Wifi Cards (ID_NET_NAME_MAC)
#  wl = wlan
#  x  = MAC
#  aabbccddffgg = MAC address of device
# -------------------------------------------------------------------------------------------------

# TP-Link USB WiFi Adapter for PC(TL-WN725N)
WLAN_INTERFACE_TPLINK="CHANGE_ME"

# Alfa AC1200 USB Wireless cards
WLAN_INTERFACE_AC1200_1="CHANGE_ME"
WLAN_INTERFACE_AC1200_2="CHANGE_ME"

# MAC Address of built-in Ethernet interface
MAC_ETH0="CHANGE_ME"

# MAC Address of built-in WiFi interface
MAC_WLAN0="CHANGE_ME"

# -------------------------------------------------------------------------------------------------
# Access Point ESSID and Password
# -------------------------------------------------------------------------------------------------
AP_ESSID="CHANGE_ME"
AP_WPA_PASSPHRASE="CHANGE_ME"

# -------------------------------------------------------------------------------------------------
# Target directory to install the scanning scripts
# -------------------------------------------------------------------------------------------------
TARGET_DIR="/root/wifi_scanning_tools"