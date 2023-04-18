#!/bin/bash

# Install necessary packages if they are not installed
if ! dpkg -s newt &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y newt
fi

# Get the name of the Linux distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
elif type lsb_release >/dev/null 2>&1; then
    OS=$(lsb_release -si)
else
    OS=$(uname -s)
fi

# Print the name of the Linux distribution
#echo "Detected Linux distribution: $OS"


# Prompt user for DHCP or static IP address
dhcp_or_static=$(whiptail --title "IP Configuration" --menu "Select IP configuration method" 15 60 2 --backtitle "Detected Linux distribution: $OS" \
"DHCP" "Obtain IP address automatically" \
"Static" "Specify static IP address" 3>&1 1>&2 2>&3)

if [[ "$dhcp_or_static" = "DHCP" ]]; then
    if [ "$OS" == "Ubuntu" ] && [ "$(lsb_release -sr)" == "20.04" ] && [ -x /usr/sbin/netplan ]; then
        # Set interface to DHCP
        interface_name=$(ip -o -4 route show to default | awk '{print $5}')
        cat <<EOF > /etc/netplan/01-netcfg.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    $interface_name:
      dhcp4: yes
EOF
        # Apply configuration
        netplan apply
        # Display confirmation message
        whiptail --msgbox "DHCP configuration applied successfully." 10 60
        exit 0
	else
        # Set DHCP
        interface_name=$(ip -o -4 route show to default | awk '{print $5}')
        cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-$interface_name

BOOTPROTO=dhcp
DEVICE=$interface_name
ONBOOT=yes
STARTMODE=auto
TYPE=Ethernet
USERCTL=no

EOF
        systemctl restart network
        whiptail --msgbox "DHCP configuration applied successfully." 10 60
        exit 0
	fi
fi

# Define default values for IP configuration
interface_name=$(ip -o -4 route show to default | awk '{print $5}')
static_ip=$(ip -o -4 addr show dev $interface_name | awk '{print $4}' | cut -d/ -f1)
netmask=$(ip -o -4 addr show dev $interface_name | awk '{print $4}' | cut -d/ -f2)
gateway=$(ip -o -4 route show to default | awk '{print $3}')
dns=$(systemd-resolve --status | awk '/DNS Servers:/ {print $3}')


# Define functions for displaying input dialogs
function display_interface_name_dialog {
    interface_name=$(whiptail --inputbox "Enter the network interface name:" 10 60 $interface_name 3>&1 1>&2 2>&3)
    if [[ -z "$interface_name" ]]; then
        whiptail --msgbox "Interface name cannot be empty." 10 60
        display_interface_name_dialog
    fi
}

function display_static_ip_dialog {
    static_ip=$(whiptail --inputbox "Enter the static IP address:" 10 60 $static_ip 3>&1 1>&2 2>&3)
    if [[ -z "$static_ip" ]]; then
        whiptail --msgbox "IP address cannot be empty." 10 60
        display_static_ip_dialog
    elif ! [[ $static_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then # Validate numbers only
        whiptail --msgbox "Invalid IP address format." 10 60
        display_static_ip_dialog
    fi

    # Check that there are exactly 4 octets.
    IFS='.' read -ra ip_arr <<< "$static_ip"
    if (( ${#ip_arr[@]} != 4 )); then
      whiptail --msgbox "Invalid IP address. Please enter an IP address with exactly 4 octets." 8 40
      display_static_ip_dialog
    fi

    # Check that no octet is higher than 255
    IFS='.' read -ra ip_arr <<< "$static_ip"
    for octet in "${ip_arr[@]}"; do
      if (( octet > 255 )); then
        whiptail --msgbox "Invalid IP address format" 8 40
        display_static_ip_dialog
      fi
    done

}


function display_netmask_dialog {
    netmask=$(whiptail --inputbox "Enter the subnet mask in CIDR notation (e.g. 24):" 10 60 $netmask 3>&1 1>&2 2>&3)
    if [[ -z "$netmask" ]]; then
        whiptail --msgbox "Subnet mask cannot be empty." 10 60
        display_netmask_dialog
    elif ! [[ $netmask =~ ^[0-9]+$ ]] || [[ $netmask -lt 0 ]] || [[ $netmask -gt 32 ]]; then
        whiptail --msgbox "Invalid subnet mask value." 10 60
        display_netmask_dialog
    fi
}

function display_gateway_dialog {
    gateway=$(whiptail --inputbox "Enter the gateway IP address:" 10 60 $gateway 3>&1 1>&2 2>&3)
    if [[ -z "$gateway" ]]; then
        whiptail --msgbox "Gateway IP address cannot be empty." 10 60
        display_gateway_dialog
    elif ! [[ $gateway =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        whiptail --msgbox "Invalid gateway IP address format." 10 60
        display_gateway_dialog
    fi
     
    # Check that there are exactly 4 octets.
    IFS='.' read -ra ip_arr <<< "$gateway"
    if (( ${#ip_arr[@]} != 4 )); then
        whiptail --msgbox "Invalid IP address. Please enter an IP address with exactly 4 octets." 8 40
        display_gateway_dialog
    fi

    IFS='.' read -ra ip_arr <<< "$gateway"
    for octet in "${ip_arr[@]}"; do
      if (( octet > 255 )); then
        whiptail --msgbox "Invalid IP address format" 8 40
        display_gateway_dialog
      fi
    done


}

function display_dns_dialog {
    dns=$(whiptail --inputbox "Enter the DNS server IP address:" 10 60 $dns 3>&1 1>&2 2>&3)
    if [[ -z "$dns" ]]; then
        whiptail --msgbox "DNS server IP address cannot be empty." 10 60
        display_dns_dialog
    fi
 
    # Check that there are exactly 4 octets.
    IFS='.' read -ra ip_arr <<< "$dns"
    if (( ${#ip_arr[@]} != 4 )); then
      whiptail --msgbox "Invalid IP address. Please enter an IP address with exactly 4 octets." 8 40
      display_dns_dialog
    fi

    IFS='.' read -ra ip_arr <<< "$dns"
    for octet in "${ip_arr[@]}"; do
      if (( octet > 255 )); then
        whiptail --msgbox "Invalid IP address format" 8 40
        display_dns_dialog
      fi
    done
}

# Display input dialogs
display_interface_name_dialog
display_static_ip_dialog
display_netmask_dialog
display_gateway_dialog
display_dns_dialog

# Write configuration to file
if [ "$OS" == "Ubuntu" ] && [ "$(lsb_release -sr)" == "20.04" ] && [ -x /usr/sbin/netplan ]; then
cat << EOF > /etc/netplan/01-netcfg.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    $interface_name:
      dhcp4: no
      addresses: [$static_ip/$netmask]
      gateway4: $gateway
      nameservers:
        addresses: [$dns]
EOF

# Apply configuration
netplan apply &
else

    cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-$interface_name

BOOTPROTO=none
DEVICE=$interface_name
IPADDR=$static_ip
PREFIX=$netmask
GATEWAY=$gateway
DNS1=$dns

EOF
    systemctl restart network
	touch /etc/cloud/cloud-init.disabled
fi

# Display confirmation message
whiptail --msgbox "Static IP address configuration applied successfully." 10 60
clear