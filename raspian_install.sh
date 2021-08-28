#!/bin/bash

# -------------------------------------------------------------------------------------------------
# WIFI Scanning Service Install Script for Raspberry Pi
# -------------------------------------------------------------------------------------------------
# This script will install and configure the necessary packagers for wifi scanning service
# 
# PLEASE Review the variables under config/variables.sh to ensure they match your system and hardware
#
# PLEASE review the files in the config directory to ensure they are configured correctly
#
# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# Prompt user for confirmation, optional argument for text to display to user
# -------------------------------------------------------------------------------------------------
prompt_confirm() {
    read -p "${1:-Continue?} [y/n]:" -n1 -r
    case $REPLY in
      [yY]) echo ; return 0 ;;
      [nN]) echo ; return 1 ;;
      *) printf "Invalid input"
    esac 
}

# -------------------------------------------------------------------------------------------------
# Prompt user to install as a service
# -------------------------------------------------------------------------------------------------
prompt_service_install() {
    read -p "${1:-Continue?} [y/n]:" -n1 -r
    case $REPLY in
      [yY]) echo ; return 0 ;;
      [nN]) echo ; return 1 ;;
      *) printf "Invalid input"
    esac 
}

# Save starting directory
SAVED_DIR=$(pwd)

# config dir
CONFIG_DIR="${SAVED_DIR}/config"

# script dir
SCRIPT_DIR="${SAVED_DIR}/scripts"

# Source configuration file 
source ${CONFIG_DIR}/variables.sh

# set terminal output colors
RED=`tput setaf 1`
GREEN=`tput setaf 2`
BLUE=`tput setaf 4`
YELLOW=`tput setaf 3`
CYAN=`tput setaf 6`
RESET=`tput sgr0`

# Optional argument to install wifi-scanning service
SERVICE_INSTALL=0

# Process commandline optional arguments
if [[ "$1" = "-s" || "$1" = "--service" ]]; then 
  SERVICE_INSTALL=1
  echo "${YELLOW}[*] wifi-scanning service will be installed ${RESET}"

elif [[ "$1" = "-h" || "$1" = "--help" ]]; then  
  echo
  echo "${CYAN}Install and configure this device for wifi scanning${RESET}"
  echo 
  echo "${CYAN}Script must be run as root${RESET}"
  echo "${CYAN}./install.sh [-s|-h] ${RESET}"
  echo "${CYAN}  -s|--service, install wifi-scanning service ${RESET}"
  echo "${CYAN}  -h|--help, display help message ${RESET}"
  echo "${CYAN}  No arguments will allow manual execution of the wifi scanning scripts${RESET}"
  echo

  exit 0

fi

# Check if we are running script as root
if [[ $(echo $EUID) -ne 0 ]]; then
   echo "${RED}[!] This script must be run as root ${RESET}"
   exit 1
fi

echo "${BLUE}************************************************************************${RESET}"
echo "${BLUE}*                                                                      *${RESET}"
echo "${BLUE}*                     Wifi Scanning Setup                              *${RESET}"
echo "${BLUE}*                                                                      *${RESET}"
echo "${BLUE}* The following external devices are utilized in this setup:           *${RESET}"
echo "${BLUE}*   - TP-LINK TL-WN725N used for the Access Point                      *${RESET}"
echo "${BLUE}*   - ALFA AC1200 AWUS036ACH used for scanning                         *${RESET}"
echo "${BLUE}*   - GlobalSat BU-353-S4 USB GPS Receiver                             *${RESET}"
echo "${BLUE}*                                                                      *${RESET}"
echo "${BLUE}************************************************************************${RESET}"
echo
echo "${YELLOW}[!] Make sure all configuration files and variables have been updated before running this script !!${RESET}"
echo
echo "${YELLOW}[!] Do not plug in any USB adapters during the install !!${RESET}"
echo
echo "${YELLOW}[!] When install is finished you will be prompted to shutdown the device${RESET}"
echo
prompt_confirm "Ready to continue?" || exit 0

# -------------------------------------------------------------------------------------------------
# Verify service install status if not added as argument
# -------------------------------------------------------------------------------------------------
if [[ ${SERVICE_INSTALL} -eq 0 ]]; then 
  prompt_service_install "Install as a service?" && SERVICE_INSTALL=1

  if [[ ${SERVICE_INSTALL} -eq 1 ]]; then
    echo "${YELLOW}[*] wifi-scanning service will be installed ${RESET}"
  fi
fi

# -------------------------------------------------------------------------------------------------
# Update and install OS packages
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Update and install apps and system...${RESET}"

apt update 
apt -y upgrade
apt -y dist-upgrade
apt -y autoremove

# Install required packages
#   hostapd dnsmasq -- used for Access Point
#   ntp ntpdate -- time sync
#   gpsd gpsd-clients -- gps 
#   libcurl4-openssl-dev libssl-dev zlib1g-dev -- hcxdump/hcxtools
apt -y install raspberrypi-kernel-headers tmux git dkms hostapd dnsmasq ntp ntpdate gpsd gpsd-clients libcurl4-openssl-dev libssl-dev zlib1g-dev  

# -------------------------------------------------------------------------------------------------
# Change SSH Host Keys
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Change SSH Host Keys...${RESET}"
rm /etc/ssh/ssh_host_*
dpkg-reconfigure openssh-server
systemctl restart ssh.service 

# -------------------------------------------------------------------------------------------------
# Disable Bluetooth
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Disable Bluetooth...${RESET}"
systemctl disable bluetooth.service
systemctl stop bluetooth.service

# -------------------------------------------------------------------------------------------------
# Unblock Wireless
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Unblock WiFi...${RESET}"
id=$(rfkill list all | grep Wireless | cut -d":" -f1)
rfkill unblock $id
rfkill list all

# -------------------------------------------------------------------------------------------------
# Update parameters for gpsd
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Update parameters for gpsd...${RESET}"

cat > /etc/default/gpsd << EOF
# Devices gpsd should collect to at boot time.
# They need to be read/writeable, either by user gpsd or the group dialout.
DEVICES="/dev/ttyUSB0"

# Other options you want to pass to gpsd
GPSD_OPTIONS="-n"

# Automatically hot add/remove USB GPS devices via gpsdctl
USBAUTO="true"
EOF

# -------------------------------------------------------------------------------------------------
# Update date and time
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Update date and time...${RESET}"

cat > /etc/ntp.conf << EOF
driftfile /var/lib/ntp/ntp.drift
logfile /var/log/ntp.log

restrict default kod nomodify notrap nopeer noquery
restrict -6 default kod nomodify notrap nopeer noquery
restrict 127.0.0.1 mask 255.255.255.0
restrict -6 ::1

# GPS Serial data reference (NTP0)
server 127.127.28.0
fudge 127.127.28.0 flag1 1 refid GPS

# GPS PPS reference (NTP1)
server 127.127.28.1 prefer
fudge 127.127.28.1 flag1 1 refid PPS
EOF

# Enable NTP service
systemctl enable ntp.service

# Set timezone 
timedatectl set-timezone Etc/UTC

ls -lrt /etc/localtime

# -------------------------------------------------------------------------------------------------
# Install driver for TP-LINK USB Adapter
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Install rtl8188eus driver for TP-Link USB Adapter...${RESET}"

# Blacklist the default driver:
echo "blacklist r8188eu" > "/etc/modprobe.d/realtek.conf"

cd /opt
git clone https://github.com/aircrack-ng/rtl8188eus.git

cd /opt/rtl8188eus

sed -i 's/CONFIG_PLATFORM_I386_PC = y/CONFIG_PLATFORM_I386_PC = n/g' Makefile
sed -i 's/CONFIG_PLATFORM_ARM64_RPI = n/CONFIG_PLATFORM_ARM64_RPI = y/g' Makefile
sed -i 's/^dkms build/ARCH=arm dkms build/' dkms-install.sh
sed -i 's/^MAKE="/MAKE="ARCH=arm\ /' dkms.conf

./dkms-install.sh

cd ${SAVED_DIR}

# -------------------------------------------------------------------------------------------------
# Install drivers for Alfa AC1200 USB Wireless cards
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Install rtl8812au driver for Alfa AC1200 USB Wireless cards...${RESET}"

cd /opt
git clone https://github.com/aircrack-ng/rtl8812au.git

cd /opt/rtl8812au

sed -i 's/CONFIG_PLATFORM_I386_PC = y/CONFIG_PLATFORM_I386_PC = n/g' Makefile
sed -i 's/CONFIG_PLATFORM_ARM64_RPI = n/CONFIG_PLATFORM_ARM64_RPI = y/g' Makefile
export ARCH=arm
sed -i 's/^MAKE="/MAKE="ARCH=arm\ /' dkms.conf

make dkms_install

cd ${SAVED_DIR}

# -------------------------------------------------------------------------------------------------
# Install aircrack-ng
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Install aircrack-ng...${RESET}"

# Install build dependencies
apt -y install build-essential autoconf automake libtool pkg-config libnl-3-dev libnl-genl-3-dev libssl-dev ethtool shtool rfkill zlib1g-dev libpcap-dev libsqlite3-dev libpcre3-dev libhwloc-dev libcmocka-dev hostapd wpasupplicant tcpdump screen iw usbutils

cd /opt
git clone https://github.com/aircrack-ng/aircrack-ng.git

cd /opt/aircrack-ng

# Generate configuration file
autoreconf -i

# Configure build information
./configure

# make and make install 
make && make install

# link libraries after install 
ldconfig

# update the list of OUIs to display manufactures
airodump-ng-oui-update

cd ${SAVED_DIR}

# -------------------------------------------------------------------------------------------------
# Disable Network-Manager
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Disable Network-Manager...${RESET}"
systemctl stop NetworkManager.service
systemctl disable NetworkManager.service

# -------------------------------------------------------------------------------------------------
# Configure perdictable naming of interfaces (ID_NET_NAME_MAC)
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Configure perdictable naming convention for network interfaces ${RESET}"

if [ -f /usr/lib/systemd/network/73-usb-net-by-mac.link ]; then
	mv /usr/lib/systemd/network/73-usb-net-by-mac.link /usr/lib/systemd/network/73-usb-net-by-mac.link.old
fi

if [ -f /usr/lib/systemd/network/99-default.link ]; then
	mv /usr/lib/systemd/network/99-default.link /usr/lib/systemd/network/99-default.link.old
fi

if [ -f /etc/udev/rules.d/70-persistent-net.rules ]; then
	mv /etc/udev/rules.d/70-persistent-net.rules /etc/udev/rules.d/70-persistent-net.rules.old
fi

if [ -f /etc/udev/rules.d/73-usb-net-by-mac.rules ]; then
	mv /etc/udev/rules.d/73-usb-net-by-mac.rules /etc/udev/rules.d/73-usb-net-by-mac.rules.old
fi

cat > /etc/udev/rules.d/70-persistent-net.rules <<EOF
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{type}=="1", ATTR{dev_id}=="0x0", ATTR{address}=="${MAC_ETH0}", KERNEL=="eth*", NAME="eth0"
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{type}=="1", ATTR{dev_id}=="0x0", ATTR{address}=="${MAC_WLAN0}", KERNEL=="wlan*", NAME="wlan0"
EOF

cp ${CONFIG_DIR}/73-usb-net-by-mac.rules /etc/udev/rules.d/73-usb-net-by-mac.rules
chmod 644 /etc/udev/rules.d/73-usb-net-by-mac.rules

systemctl restart systemd-udevd
systemctl status systemd-udevd

# -------------------------------------------------------------------------------------------------
# Configure network interfaces
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Configure network interfaces${RESET}"

cp ${CONFIG_DIR}/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf
chmod 644 /etc/wpa_supplicant/wpa_supplicant.conf

mv /etc/network/interfaces /etc/network/interfaces.old

cat > /etc/network/interfaces << EOF
auto lo
iface lo inet loopback

auto eth0
allow-hotplug eth0
iface eth0 inet dhcp

# wlan0: Built-in WiFi interface (Broadcom 43430)
# Used to connect to Internet (when eth0 not used)
auto wlan0
allow-hotplug wlan0
iface wlan0 inet manual
  wpa-roam /etc/wpa_supplicant/wpa_supplicant.conf
iface default inet dhcp

# WiFi USB Adapter TP-Link
# Realtek Semiconductor Corp. RTL8188EUS 802.11n Wireless Network Adapter
# Used to set up AP at boot for pwnbox access via WiFi
allow-hotplug ${WLAN_INTERFACE_TPLINK}
iface ${WLAN_INTERFACE_TPLINK} inet static
  address 192.168.150.1
  netmask 255.255.255.0
  ip route add -net 192.168.150.0 netmask 255.255.255.0 gw 192.168.150.1

# Alfa AC1200 USB Wireless cards
# Disabled by default at boot
iface ${WLAN_INTERFACE_AC1200_1} inet manual
ifdown ${WLAN_INTERFACE_AC1200_1}

# WiFi USB Adapter Alfa AWUS036ACH Realtek RTL8812AU
# Disabled by default at boot
iface ${WLAN_INTERFACE_AC1200_2} inet manual
ifdown ${WLAN_INTERFACE_AC1200_2}
EOF

# -------------------------------------------------------------------------------------------------
# Configure hostapd and enable it as a service
#
# The service will be disabled.  We will manually start it in our scripts
#
# - TP-LINK USB Adapter will be used for the AP
# - Will use WPA2
# - Will use MAC address whitelisting
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Configure hostapd...${RESET}"

if [[ ! -d /etc/hostapd ]]; then
    echo "${RED}[~] /opt/hostapd directory not found, exiting...${RESET}"
    exit 1
fi 

# configure hostapd
cat > /etc/hostapd/hostapd.conf << EOF
interface=${WLAN_INTERFACE_TPLINK}
driver=nl80211
hw_mode=g
channel=6
country_code=US

ssid=${AP_ESSID}
auth_algs=1
wpa=2
wpa_passphrase=${AP_WPA_PASSPHRASE}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
wpa_group_rekey=86400
ieee80211n=1

macaddr_acl=1
accept_mac_file=/etc/hostapd/hostapd.accept
EOF

# copy hostapd.accept
cp ${CONFIG_DIR}/hostapd.accept /etc/hostapd/hostapd.accept
chmod 644 /etc/hostapd/hostapd.accept

# enable hostapd as a service
cat > /etc/default/hostapd << EOF
DAEMON_CONF="/etc/hostapd/hostapd.conf"
EOF

# this is require for raspberry pi devices
systemctl unmask hostapd.service

systemctl enable hostapd.service

# -------------------------------------------------------------------------------------------------
# Configure dnsmasq
#
# The service will be disabled.  We will manually start it in our scripts
#
# - TP-LINK USB Adapter will be used for the AP
#
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Configure dnsmaq...${RESET}"

cat > /etc/dnsmasq.conf << EOF
interface=${WLAN_INTERFACE_TPLINK}
bind-interfaces
dhcp-range=192.168.150.2,192.168.150.5,12h
listen-address=192.168.150.1

log-queries
log-dhcp

dhcp-authoritative
dhcp-option=3,192.168.150.1
dhcp-option=6,192.168.150.1
server=8.8.8.8
EOF

systemctl enable dnsmasq.service

# -------------------------------------------------------------------------------------------------
# Install hcxtools and hcxdumptool
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Install hcxtools and hcxdumptool...${RESET}"

cd /opt

git clone https://github.com/ZerBea/hcxtools.git
git clone https://github.com/ZerBea/hcxdumptool.git

cd /opt/hcxtools/
make && make install

cd /opt/hcxdumptool
make && make install

cd ${SAVED_DIR}

# -------------------------------------------------------------------------------------------------
# Copy scanning scripts to target directory
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Copying scripts to ${TARGET_DIR}...${RESET}"

# Copy the script into the destination directory
mkdir ${TARGET_DIR}

cp ${SCRIPT_DIR}/run_airodump.sh ${TARGET_DIR}/run_airodump.sh
chmod 755 ${TARGET_DIR}/run_airodump.sh

cp ${SCRIPT_DIR}/run_hcxdump.sh ${TARGET_DIR}/run_hcxdump.sh
chmod 755 ${TARGET_DIR}/run_hcxdump.sh

cp ${CONFIG_DIR}/variables.sh ${TARGET_DIR}/variables.sh
chmod 755 ${TARGET_DIR}/variables.sh

# Add the full path to source the variables.sh file in the scripts
VAR_FILE_PATH=${TARGET_DIR}/variables.sh

sed -i "s|VARIABLE_PATH|${VAR_FILE_PATH}|" ${TARGET_DIR}/run_airodump.sh
sed -i "s|VARIABLE_PATH|${VAR_FILE_PATH}|" ${TARGET_DIR}/run_hcxdump.sh

# -------------------------------------------------------------------------------------------------
# Install wifi-scanning service
# -------------------------------------------------------------------------------------------------
if [[ ${SERVICE_INSTALL} -eq 1 ]]; then 

  echo "${YELLOW}[~] Install wifi-scanning service...${RESET}"

cat > /etc/systemd/system/wifi-scanning.service << EOF
[Unit]
Description=Wifi Monitoring via airodump-ng
Requires=network-online.target gpsd.service
After=network.target gpsd.service ntp.service

[Service]
Type=simple
User=root
ExecStart=${TARGET_DIR}/run_airodump.sh start
ExecStop=${TARGET_DIR}/run_airodump.sh stop
RemainAfterExit=y

[Install]
WantedBy=multi-user.target
EOF

  # enable as a service
  chmod 644 /etc/systemd/system/wifi-scanning.service
  systemctl enable wifi-scanning.service

else

  echo "${YELLOW}[~] Skipping installation of wifi_scanning service...${RESET}"

fi

# -------------------------------------------------------------------------------------------------
# Add aliases to users profile
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Adding aliases to $BASE_USER_NAME profile ...${RESET}"
echo "" >> /home/$BASE_USER_NAME/.bashrc
echo "alias astart='sudo /root/wifi_scanning_tools/run_airodump.sh start'" >> /home/$BASE_USER_NAME/.bashrc
echo "alias astop='sudo /root/wifi_scanning_tools/run_airodump.sh stop'" >> /home/$BASE_USER_NAME/.bashrc
echo "alias hstart='sudo /root/wifi_scanning_tools/run_hcxdump.sh start'" >> /home/$BASE_USER_NAME/.bashrc
echo "alias hstop='sudo /root/wifi_scanning_tools/run_hcxdump.sh stop'" >> /home/$BASE_USER_NAME/.bashrc
echo "alias shutdown='sudo shutdown -h 1'" >> /home/$BASE_USER_NAME/.bashrc
echo "alias reboot='sudo shutdown -r now'" >> /home/$BASE_USER_NAME/.bashrc

# -------------------------------------------------------------------------------------------------
# Cleanup and reboot
# -------------------------------------------------------------------------------------------------
echo "${GREEN}[+] Installation is complete!  The system will shutdown now.${RESET}"

prompt_confirm "Shutdown Now?" || exit 0

shutdown -h now