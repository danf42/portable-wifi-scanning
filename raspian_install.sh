#!/bin/bash
exec > >(tee -a /var/log/portable_wifi_installer.log) 2>&1

# -------------------------------------------------------------------------------------------------
# Before getting started...
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
# Logger helper
# -------------------------------------------------------------------------------------------------
logger() {
  DT=$(date '+%Y/%m/%d %H:%M:%S')
  echo "$DT $0: $1"
}

# Check if we are running script as root
if [[ $(echo $EUID) -ne 0 ]]; then
   echo "${RED}[!] This script must be run as root ${RESET}"
   exit 1
fi

# Don't prompt for interaction
export DEBIAN_FRONTEND=noninteractive

# Save starting directory
SAVED_DIR=$(pwd)

# config dir
CONFIG_DIR="${SAVED_DIR}/config"

# script dir
SCRIPT_DIR="${SAVED_DIR}/scripts"

# Check for Production Configuration files
if [ -d "${CONFIG_DIR}_prod" ]; then
    echo "Staging production configuration files..."
    cp -r ${CONFIG_DIR}_prod/* ${CONFIG_DIR}
else
    echo "did not find ${CONFIG_DIR}_prod"
fi  

# Source configuration file 
source ${CONFIG_DIR}/variables.sh

# set terminal output colors
RED=`tput setaf 1`
GREEN=`tput setaf 2`
BLUE=`tput setaf 4`
YELLOW=`tput setaf 3`
CYAN=`tput setaf 6`
RESET=`tput sgr0`

echo "${BLUE}************************************************************************${RESET}"
echo "${BLUE}*                                                                      *${RESET}"
echo "${BLUE}*                     Wifi Scanning Setup                              *${RESET}"
echo "${BLUE}*                                                                      *${RESET}"
echo "${BLUE}* The following external devices are utilized in this setup:           *${RESET}"
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
# Create directories required for setup
# -------------------------------------------------------------------------------------------------
# List of names
dirs_to_create=("${REPO_DIR}" "${TOOL_DIR}" "${DRIVER_DIR}")

# Loop through each name
for dirname in "${dirs_to_create[@]}"; do
  # Check if the directory already exists
  if [ ! -d "$dirname" ]; then
    # Create the directory if it doesn't exist
    mkdir -p "$dirname"
    echo "Directory $dirname created."
  else
    echo "Directory $dirname already exists."
  fi
done

# -------------------------------------------------------------------------------------------------
# Update and install OS packages
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Update and install apps and system...${RESET}"

apt update 
apt -y upgrade
apt -y dist-upgrade
apt -y autoremove
apt -y clean

# Install required packages
apt -y install raspberrypi-kernel-headers tmux git dkms hostapd dnsmasq ntp ntpdate \
 dhcpcd5 ntpsec gpsd gpsd-clients libcurl4-openssl-dev \
 tshark python3-pip python3-venv python3-openssl curl vim git wget \
 ipcalc unzip openssl net-tools dnsutils nfs-common smbclient nmap \
 netdiscover tshark snmp onesixtyone libssl-dev zlib1g-dev \
 bridge-utils wireless-tools monit
 
# -------------------------------------------------------------------------------------------------
# Change SSH Host Keys
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Change SSH Host Keys...${RESET}"
rm /etc/ssh/ssh_host_*
dpkg-reconfigure openssh-server
systemctl restart ssh.service

# -------------------------------------------------------------------------------------------------
# Update Message Of The Day
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Update motd banner...${RESET}"
if [ -f ${CONFIG_DIR}/motd ]; then
    cp ${CONFIG_DIR}/motd /etc/motd
fi

# -------------------------------------------------------------------------------------------------
# Unblock Wireless and Bluetooth Service
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Unblock Wireless and Bluetooth Service...${RESET}"

id=$(rfkill list all | grep Wireless | cut -d":" -f1)
rfkill unblock $id

id=$(rfkill list all | grep Bluetooth | cut -d":" -f1)
rfkill unblock $id

rfkill list all

# -------------------------------------------------------------------------------------------------
# Configure GPS 
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Update parameters for gpsd...${RESET}"

systemctl unmask gpsd.service
systemctl disable gpsd.service

cat > /etc/default/gpsd << EOF
# Devices gpsd should collect to at boot time.
# They need to be read/writeable, either by user gpsd or the group dialout.
DEVICES="/dev/ttyUSB0"

# Other options you want to pass to gpsd
GPSD_OPTIONS="-F /var/run/gpsd.sock -b -n"

# Automatically hot add/remove USB GPS devices via gpsdctl
USBAUTO="true"

# Start the gpsd daemon automatically at boot time
START_DAEMON="true"
EOF

echo "${YELLOW}[~] Create udev to watch for gps device...${RESET}"

# Information is obtained from command
#  > udevadm info -a -n /dev/ttyUSB0
# Note: parameters will need to change for different GSP device

cat > /etc/udev/rules.d/99-usb-gps.rules << EOF
SUBSYSTEM=="tty", ATTRS{idVendor}=="067b", ATTRS{idProduct}=="23a3",ENV{SYSTEMD_WANTS}="gpsd.service"
EOF

chmod 644 /etc/udev/rules.d/99-usb-gps.rules

echo "${YELLOW}[~] Update gspd.service ...${RESET}"

cat > /usr/lib/systemd/system/gpsd.service << EOF
[Unit]
Description=GPS (Global Positioning System) Daemon
Requires=gpsd.socket

[Service]
Type=forking
EnvironmentFile=-/etc/default/gpsd
ExecStart=/usr/sbin/gpsd \$GPSD_OPTIONS \$OPTIONS \$DEVICES

[Install]
WantedBy=multi-user.target
Also=gpsd.socket
EOF

echo "${YELLOW}[~] Reload services for gpsd updates to take effect ...${RESET}"
systemctl restart systemd-udevd
systemctl daemon-reload

# -------------------------------------------------------------------------------------------------
# Update date and time
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Update date and time...${RESET}"

cat > /etc/ntpsec/ntp.conf << EOF
driftfile /var/lib/ntpsec/ntp.drift
leapfile /usr/share/zoneinfo/leap-seconds.list
logfile /var/log/ntp.log

# By default, exchange time with everybody, but don't allow configuration.
restrict default kod nomodify nopeer noquery limited

# Local users may interrogate the ntp server more closely.
restrict 127.0.0.1
restrict ::1

# GPS Serial data reference
server 127.127.28.0 minpoll 4 maxpoll 4
fudge 127.127.28.0 time1 0.0 refid GPS

# GPS PPS reference
server 127.127.28.1 minpoll 4 maxpoll 4 prefer
fudge 127.127.28.1 refid PPS

# Ingore time difference
tinker panic 0
EOF

# Needed for ntpsec metrics
mkdir /var/log/ntpsec/
chown ntpsec:ntpsec /var/log/ntpsec/

# Enable NTP service
systemctl enable ntpsec.service

# Set timezone 
timedatectl set-timezone Etc/UTC

ls -lrt /etc/localtime

# -------------------------------------------------------------------------------------------------
# Install driver for TP-LINK USB Adapter
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Install rtl8188eus driver for TP-Link USB Adapter...${RESET}"

# Blacklist the default driver:
echo "blacklist r8188eu" > "/etc/modprobe.d/realtek.conf"

cd ${DRIVER_DIR}
git clone https://github.com/lwfinger/rtw88

cd ${DRIVER_DIR}/rtw88

# make and make install 
make clean && make && make install && sudo make install_fw

cd ${HOME}

echo "${RED}************************************************************************${RESET}"
echo "${RED}*                          NOTICE!!                                    *${RESET}"
echo "${RED}*         Wireless drivers will need to be reinstalled                 *${RESET}"
echo "${RED}*             everytime the Kernel is updated!                         *${RESET}"
echo "${RED}*                                                                      *${RESET}"
echo "${RED}************************************************************************${RESET}"

# -------------------------------------------------------------------------------------------------
# Install aircrack-ng
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Install aircrack-ng...${RESET}"

# Install build dependencies
apt -y install build-essential autoconf automake libtool pkg-config libnl-3-dev libnl-genl-3-dev libssl-dev \
  ethtool shtool rfkill zlib1g-dev libpcap-dev libsqlite3-dev libpcre2-dev libhwloc-dev libcmocka-dev \
  hostapd wpasupplicant tcpdump screen iw usbutils expect

cd ${TOOL_DIR}
git clone https://github.com/aircrack-ng/aircrack-ng.git

cd ${TOOL_DIR}/aircrack-ng

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

cd ${HOME}

# -------------------------------------------------------------------------------------------------
# Disable and Remove NetworkManager
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Disable Network-Manager...${RESET}"
systemctl stop NetworkManager.service
systemctl disable NetworkManager.service
apt -y purge network-manager

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

chmod 644 /etc/udev/rules.d/70-persistent-net.rules

cp ${CONFIG_DIR}/73-usb-net-by-mac.rules /etc/udev/rules.d/73-usb-net-by-mac.rules
chmod 644 /etc/udev/rules.d/73-usb-net-by-mac.rules

systemctl restart systemd-udevd
systemctl status systemd-udevd

# -------------------------------------------------------------------------------------------------
# Configure systemd-netword
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Configure systemd-networkd${RESET}"

cat > /etc/systemd/network/00-eth0.network << EOF
[Match]
Name=eth0

[Network]
DHCP=yes
LinkLocalAddressing=no
EOF

chmod 644 /etc/systemd/network/00-eth0.network

cat > /etc/systemd/network/01-wlan0.network << EOF
[Match]
Name=wlan0

[Network]
DHCP=no
Address=192.168.150.1/24
EOF

chmod 644 /etc/systemd/network/01-wlan0.network

systemctl unmask systemd-networkd
systemctl enable systemd-networkd

networkctl

# -------------------------------------------------------------------------------------------------
# Ignore wlan0 from dhcpd
# -------------------------------------------------------------------------------------------------
cat >> /etc/dhcpcd.conf << EOF

# Deny DHCP from controllering wlan0 interface
denyinterfaces wlan0 >> /etc/dhcpcd.conf
EOF

# -------------------------------------------------------------------------------------------------
# Configure network interfaces
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Configure network interfaces${RESET}"

cp ${CONFIG_DIR}/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf
chmod 644 /etc/wpa_supplicant/wpa_supplicant.conf

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
interface=${MGMT_INTERFACE}
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
interface=${MGMT_INTERFACE}
bind-interfaces
dhcp-range=192.168.150.2,192.168.150.5,12h
listen-address=192.168.150.1

log-queries
log-dhcp

dhcp-authoritative
dhcp-option=3,192.168.150.1
dhcp-option=6,192.168.150.1
server=8.8.8.8
server=9.9.9.9
EOF

systemctl unmask dnsmasq.service
systemctl enable dnsmasq.service

# -------------------------------------------------------------------------------------------------
# Install hcxtools and hcxdumptool
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Install hcxtools and hcxdumptool...${RESET}"

cd ${TOOL_DIR}

git clone https://github.com/ZerBea/hcxtools.git
git clone https://github.com/ZerBea/hcxdumptool.git

cd ${TOOL_DIR}/hcxtools/
make && make install

cd ${TOOL_DIR}/hcxdumptool
make && make install

cd ${SAVED_DIR}

# -------------------------------------------------------------------------------------------------
# Install Docker
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Installing Docker...${RESET}"
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove $pkg; done

# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get -y install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  bookworm stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo service docker enable
sudo service docker start

usermod -aG docker ${BASE_USER_NAME}

# -------------------------------------------------------------------------------------------------
# Install Gowitness
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Installing Gowitness Docker Image...${RESET}"
docker pull ghcr.io/sensepost/gowitness:latest

# -------------------------------------------------------------------------------------------------
# Git Pull eaphammer
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Git Pull eaphammer...${RESET}"
cd ${TOOL_DIR}

git clone https://github.com/s0lst1c3/eaphammer.git

cd ${TOOL_DIR}/eaphammer
echo y | sudo ./raspbian-setup

cd ${HOME}

# -------------------------------------------------------------------------------------------------
# Git Pull bettercap
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Git Pull bettercap...${RESET}"
cd ${TOOL_DIR}

git clone https://github.com/danf42/bettercap.git

cd ${TOOL_DIR}/bettercap
docker build -t bettercap .

cd ${HOME}

# -------------------------------------------------------------------------------------------------
# Install Kismet
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Installing Kismet...${RESET}"

mkdir -m 0755 -p /etc/apt/keyrings/
curl -fsSL https://www.kismetwireless.net/repos/kismet-release.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/kismet-release.gpg

cat > /etc/apt/sources.list.d/kismet-release.list << EOF
deb [arch=arm64 trusted=yes] https://www.kismetwireless.net/repos/apt/release/bookworm bookworm main
EOF

chmod 644 /etc/apt/sources.list.d/kismet-release.list

apt-get update
apt -y install kismet

usermod -aG kismet ${BASE_USER_NAME}

# -------------------------------------------------------------------------------------------------
# Enable Packet Forwarding
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Enable Packet Forwarding...${RESET}"
sed -i '/#net.ipv4.ip_forward=1/s/^#//g' /etc/sysctl.conf

# -------------------------------------------------------------------------------------------------
# Git pull fluker
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Git pull fluker...${RESET}"

sudo -H -u ${BASE_USER_NAME} /bin/bash -c "cd ${REPO_DIR} && \
  git clone https://github.com/danf42/fluker.git"

# -------------------------------------------------------------------------------------------------
# Copy scanning scripts to target directory
# -------------------------------------------------------------------------------------------------
echo "${YELLOW}[~] Copying scripts to ${TARGET_DIR}...${RESET}"

# Copy the script into the destination directory
mkdir ${TARGET_DIR}

cp ${SCRIPT_DIR}/*.sh ${TARGET_DIR}/
chmod 755 ${TARGET_DIR}/*.sh

cp ${CONFIG_DIR}/variables.sh ${TARGET_DIR}/variables.sh
chmod 755 ${TARGET_DIR}/variables.sh

# Add the full path to source the variables.sh file in the scripts
VAR_FILE_PATH=${TARGET_DIR}/variables.sh

sed -i "s|VARIABLE_PATH|${VAR_FILE_PATH}|" ${TARGET_DIR}/run_airodump.sh

# -------------------------------------------------------------------------------------------------
# Adjust Permissions
# -------------------------------------------------------------------------------------------------
chown -R ${BASE_USER_NAME}:${BASE_USER_NAME} ${REPO_DIR}

# -------------------------------------------------------------------------------------------------
# Configure monit to monitor important services
# -------------------------------------------------------------------------------------------------
systemctl unmask monit.service
systemctl enable monit.service

echo "${BLUE}[~] Monitor dnsmasq.server ...${RESET}"
cat > /etc/monit/conf.d/dnsmasq.conf << EOF
check process dnsmasq with pidfile /var/run/dnsmasq.pid
    start program = "/etc/init.d/dnsmasq start"
    stop program  = "/etc/init.d/dnsmasq stop"
    if not exist then restart
    if failed port 53 type udp protocol dns then restart
    if failed port 53 type tcp protocol dns then restart
    if 5 restarts within 5 cycles then alert
EOF

chmod 644 /etc/monit/conf.d/*.conf

# -------------------------------------------------------------------------------------------------
# Cleanup and reboot
# -------------------------------------------------------------------------------------------------
apt -y autoremove
apt -y clean

echo "${GREEN}[+] Installation is complete! ${RESET}"

prompt_confirm "Shutdown Now?" || exit 0

shutdown -h now