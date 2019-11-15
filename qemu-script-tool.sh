#!/bin/bash

# Copyright (c) 2019 zizzu.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program.  If not, see <http://www.gnu.org/licenses/>.

set -euo pipefail

VERSION="0.1"
red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
normal=$(tput sgr0)

MACVTAPSETUP="setup_tap() {
    res=\$(ip link show | grep TAPNAME)
    if [ \"\$res\" == \"\" ];then
        echo \"Creating TAPNAME\"
        sudo ip link add link IFACE name TAPNAME type macvtap
        sudo ip link set TAPNAME address ADDR up
	tap=\"/dev/tap\$(cat /sys/class/net/TAPNAME/ifindex)\"
        sudo chown USER.GROUP \$tap
        sudo chmod g+rw \$tap
    else
        echo \"TAPNAME already exists skipping...\"
    fi
}
setup_tap
"

MACVTAP="-net nic,model=virtio,macaddr=ADDR -net tap,fd=3 3<>/dev/tap\$(cat /sys/class/net/TAPNAME/ifindex)"

LOCALNET="-netdev user,id=user0,net=192.168.20.0/24,dhcpstart=192.168.20.20"
LOCALNET2="-device e1000,netdev=user0"

QEMU="qemu() {
    /usr/bin/qemu-system-x86_64 \\
        -show-cursor \\
        -no-user-config -nodefaults \\
        -rtc base=utc,driftfix=slew \\
        -bios /usr/share/qemu/bios.bin \\
	-drive file=DRIVE \\
	-drive media=cdrom,file=ISO,readonly \\
	-enable-kvm -machine type=pc,accel=kvm \\
        -cpu host -smp CORES,sockets=SOCKETS,cores=CORES,threads=THREADS \\
        -m MEM \\
        NET \\
	-audiodev pa,id=pulse,server=/run/user/\$(id -u)/pulse/native \\
	-soundhw hda \\
	-display sdl,gl=on -vga none -device virtio-vga,xres=1440,yres=900 \\
	-sandbox on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny
}
qemu
"

function printe () {
    # redirect output to stderr else overlapping output
    printf "%s%s%s\n" "$red" "$1" "$normal" >&2
}

function printw () {
    printf "%s%s%s\n" "$yellow" "$1" "$normal" >&2
}

function printk () {
    printf "%s%b%s\n" "$green" "$1" "$normal" >&2
}

function isdigit () {
    # 0 is true in bash
    [[ "$1" =~ ^[1-9][0-9]*$ ]] && return 0
    return 1 
}

function readvalue () {
    while true
    do
        read -p "$1" value
        isdigit "$value" && break
    done

    echo $value
}

function cpuinfo () {
    printf "This machine cpu info:\n" >&2
    lscpu | grep -E '^Thread|^Core|^Socket|^CPU\('
}

function iso () {
    while true;do
        read -ep "Select cdrom iso file (tab autocomplete): " file
        local file=$(realpath -m "$file")
        [ -f $file ] && [[ "$file" =~ \.iso$ ]] && break
        printe "Not an iso file!"
    done

    printk "Selected $file"
    echo "$file"
}

function new_drive () {
    while true;do
        read -ep "Directory for the disk file (tab autocomplete): " dir
        local dir=$(realpath -m "$dir")
        [ -d "$dir" ] && [ -w "$dir" ] && break
        printe "Invalid directory $dir!" 
    done
    
    local disk_size=$(readvalue "Disk size in GB: ")
    local path="$dir/$1.qcow2"

    [ -f "$path" ] && printe "File $path exists!" && exit 1 
    
    printw "Creating disk file as $path size $disk_size GB..."
    qemu-img create -f qcow2 "$path" "${disk_size}G" >&2
    printk "Created $path"

    echo "$path"
}

function random_mac () {
    local hexchars="0123456789ABCDEF"
    local end=$( for i in {1..6}; \
           do echo -n \
           ${hexchars:$(( $RANDOM % 16 )):1}; \
           done | sed -e 's/\(..\)/:\1/g' )
    echo "1A:46:0B$end"
}

function get_ifaces () {
    local ifaces=$(ip link | sed '/^ /d ; s/^[0-9]*: \([a-z0-9]*\):.*/\1/')
    echo "$ifaces"
}

function print_ifaces () {
    printf "%-20s %10s\n" "NAME" "TYPE" >&2
    for i in $(get_ifaces);do
        local itype=$(get_iface_type $i)
        printf "%-20s %10s\n" "$i" "$itype" >&2
    done
}

function select_user () {
    while true;do
        read -e -p  "Select the user that will use this interface: " -i "$(whoami)" user
        grep -q -o "^$user:" /etc/passwd && break
    done

    echo "$user"
}

function select_group () {
    while true;do
        read -e -p  "Select group: " -i "$(groups | cut -d' ' -f 1)" group
        grep -q -o "^$group:" /etc/group && break
    done

    echo "$group"
}


function select_iface () {
    printk "Select interface:"
    print_ifaces
    
    local ifaces=$(get_ifaces)
    printf -v ifaces "%s\n" "${ifaces[@]}" #array to string
    while true; do
        read -p "Network interface: " iface
        [[ "$ifaces" =~ $iface ]] && break
    done

    echo "$iface"
}

function macvtap () {
    addr=$(random_mac)
    local iface="$1"
    local user="$(select_user)"
    local group="$(select_group)"
    read -p "Select a name for the new interface: " tapname
    printk "New macaddress $addr"
    MACVTAPSETUP="$(sed "s/IFACE/$iface/ ; \
             s/USER/$user/ ; \
             s/GROUP/$group/ ; \
             s/TAPNAME/$tapname/g ; \
             s/ADDR/$addr/" <<< "$MACVTAPSETUP")"
    MACVTAP="$(sed "s/ADDR/$addr/ ; s/TAPNAME/$tapname/" <<< "$MACVTAP")"
    QEMU="$(sed "s| NET| ${MACVTAP}|" <<< "$QEMU")"
    QEMU="${MACVTAPSETUP}\n\n${QEMU}"
}

function share_ports () {
    printk "You can now forward tcp/udp incoming connections to a port on the guest\n\
this allow for example using servers in the guest via the loopback interface\n\
the format is tcp/udp:address:port-:port separated by spaces\n\
Es: tcp:127.0.0.1:5000-:22 udp:127.0.0.1:5001-:23"

    while true;do
        read -e -p "Port forwarding rules (leave empty to skip): " ports
        ok=0
        for p in $ports;do
           ! [[ "$p" =~ (tcp|udp):[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\:[0-9]+\-\:[0-9]+ ]] && ok=1
           [ $ok -eq 1 ] && break
        done
        [ $ok -eq 0 ] && break
    done

    for p in $ports;do
        LOCALNET="${LOCALNET},hostfwd=${p}"
    done
}

function network_type () {
    printk "Select networking, macvtap does not work on wireless devices"
    while true;do
        read -e -p "Networking (none, user, macvtap): " -i "user" net
       [[ "$net" =~ ^none$|^user$|^macvtap$ ]] && break
    done

    case $net in
        none )
           QEMU="$(sed "/^ *NET.*/d" <<< "$QEMU")"
           ;;
        user )
           share_ports
           LOCALNET="$LOCALNET $LOCALNET2"
           QEMU="$(sed "s| NET| $LOCALNET|" <<< "$QEMU")"
           ;; 
        macvtap )
           local iface=$(select_iface)
           macvtap "$iface"
           ;;
    esac
}

# from some opensuse code, type of network interface
function get_iface_type () {
    local IF=$1 TYPE
    test -n "$IF" || return 1
    test -d /sys/class/net/$IF || return 2
    case "`cat /sys/class/net/$IF/type`" in
            1)
                TYPE=eth
                # Ethernet, may also be wireless, ...
                if test -d /sys/class/net/$IF/wireless -o \
                        -L /sys/class/net/$IF/phy80211 ; then
                    TYPE=wlan
                elif test -d /sys/class/net/$IF/bridge ; then
                    TYPE=bridge
                elif test -f /proc/net/vlan/$IF ; then
                    TYPE=vlan
                elif test -d /sys/class/net/$IF/bonding ; then
                    TYPE=bond
                elif test -f /sys/class/net/$IF/tun_flags ; then
                    TYPE=tap
                elif test -d /sys/devices/virtual/net/$IF ; then
                    case $IF in
                      (dummy*) TYPE=dummy ;;
                    esac
                fi
                ;;
           24)  TYPE=eth ;; # firewire ;; # IEEE 1394 IPv4 - RFC 2734
           32)  # InfiniBand
            if test -d /sys/class/net/$IF/bonding ; then
                TYPE=bond
            elif test -d /sys/class/net/$IF/create_child ; then
                TYPE=ib
            else
                TYPE=ibchild
            fi
                ;;
          512)  TYPE=ppp ;;
          768)  TYPE=ipip ;; # IPIP tunnel
          769)  TYPE=ip6tnl ;; # IP6IP6 tunnel
          772)  TYPE=loopback ;;
          776)  TYPE=sit ;; # sit0 device - IPv6-in-IPv4
          778)  TYPE=gre ;; # GRE over IP
          783)  TYPE=irda ;; # Linux-IrDA
          801)  TYPE=wlan_aux ;;
        65534)  TYPE=tun ;;
    esac
    # The following case statement still has to be replaced by something
    # which does not rely on the interface names.
    case $IF in
        ippp*|isdn*) TYPE=isdn;;
        mip6mnha*)   TYPE=mip6mnha;;
    esac
    test -n "$TYPE" && echo $TYPE && return 0
    return 3
}

function saveas () {
    while true;do
        read -e -p "Save as: " -i "$1" name
        path="$(realpath -m ${name})"
        [[ "$path" =~ ^.*/ ]] && dir="$BASH_REMATCH"
    
        if test -d "$path" ; then
            printe "Invalid file $path is a directory" ; continue
        elif test ! -e "$dir" ; then
            printe "Directory $dir does not exists" ; continue
        elif test ! -w "$dir" ; then
            printe  "Can't write to directory $dir" ; continue
        elif test -f "$path" ; then
            printe "File $path already exists" ; continue
        else
            QEMU="#!/bin/bash\n\n$QEMU"
    
            QEMU="$(sed "s:ISO:$iso: ; \
                s:DRIVE:$drive: ; \
                s/CORES/$cores/g ; \
                s/SOCKETS/$sockets/ ; \
                s/THREADS/$threads/ ; \
                s/MEM/$mem/" <<< "$QEMU")"
    
            echo -e "$QEMU" > "$path"
            chmod +x "$path"
    
            printk "Saved as $path"
            break
        fi
    done
}

printk "$0 $VERSION\n"

read -p "Machine name: " machine

iso=$(iso)
drive=$(new_drive $machine)
cpuinfo
sockets=$(readvalue "Cpu sockets: ")
cores=$(readvalue "Cpu cores: ")
threads=$(readvalue "Cpu threads: ")
mem=$(readvalue "Memory size in MB: ")
network_type

printk "Generating script..."
saveas "$machine.sh"
