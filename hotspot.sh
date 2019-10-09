#!/bin/bash
# Simple access point no routing, no dhcp, no dns
#
# Edit /etc/wpa_supplicant/wpa_supplicant.conf:
#
# ctrl_interface=/var/run/wpa_supplicant
# ctrl_interface_group=wheel
#
# Hotspot
# network={
#  ssid="YOURSSIDHERE"
#  mode=2
#  key_mgmt=WPA-PSK
#  psk="YOURPASSHERE"
#  frequency=2437
# }

INTF=YOURWIFIINTERFACEHERE

function _start() {
	echo "Starting AP"
	if [ -z `pidof wpa_supplicant` ];then
		sudo wpa_supplicant -B -i $INTF -c /etc/wpa_supplicant/wpa_supplicant.conf
	else
		echo "wpa_supplicant already started"
	fi

	echo "Assigning ip to wlan"
	if [ -z `ip a s $INTF | grep -o 10\.42\.0\.1` ];then
		sudo ip addr add 10.0.0.1/24 dev $INTF
	else
		echo "ip address already assigned"
	fi
}

function _stop(){
	echo "Stopping AP"
	sudo ip addr del 10.0.0.1/24 dev $INTF
	sudo killall wpa_supplicant
}

case "$1" in
	start)
		_start
		;;
	stop)
		_stop
		;;
	*)
		echo "Usage start | stop"
		;;
esac
