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

# TOOLS:
#
# Scale resolution inside the guest: (no needed anymore, using virtio-vga on all the options)
# xrandr | grep -oP "^ +\d+x\d+" | awk '{print NR-1,$0}'
# then xrandr -S NUMBER
#
# 

set -euo pipefail

AUTHOR="zizzu"
VERSION="0.3"
# man tput and terminfo
red=$(tput bold && tput setaf 1)
green=$(tput bold && tput setaf 2)
yellow=$(tput bold && tput setaf 3)
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

CONSOLE="-nographic -vga virtio -serial mon:stdio"
# if virtio-vga does not work in normal graphic mode use this line
#NORMAL="-display gtk -vga qxl -usb -device usb-ehci,id=ehci -device usb-tablet,bus=usb-bus.0"
NORMAL="-display gtk -vga none -device virtio-vga -usb -device usb-ehci,id=ehci -device usb-tablet,bus=usb-bus.0"
#ACCELL="-display sdl,gl=on -vga none -device virtio-vga,xres=1440,yres=900"
ACCELL="-display sdl,gl=on -vga none -device virtio-vga -usb -device usb-ehci,id=ehci -device usb-tablet,bus=usb-bus.0"

SHARED="-fsdev local,security_model=passthrough,id=fsdev0,path=FOLDER -device virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=hostshare"

#-drive file=DRIVE
#-drive media=cdrom,file=ISO,readonly
#-rtc base=utc,driftfix=slew
QEMU="qemu() {
    /usr/bin/qemu-system-x86_64 \\
        -show-cursor \\
        -parallel none \\
        -no-user-config -nodefaults \\
        -rtc clock=host,base=localtime \\
        -bios BIOS \\
        -enable-kvm -machine type=pc,accel=kvm \\
        -cpu host -smp sockets=SOCKETS,cores=CORES,threads=THREADS \\
        -m MEM \\
        NET \\
        -audiodev pa,id=pulse,server=/run/user/\$(id -u)/pulse/native \\
        -soundhw hda \\
        DISPLAY \\
        SHARED \\
        -drive media=cdrom,file=ISO,readonly,id=cd1,if=none \\
        -device ide-cd,bus=ide.1,drive=cd1 \\
        -object iothread,id=io1 \\
        -device virtio-blk-pci,drive=rootfs,iothread=io1 \\
        -drive file=DRIVE,id=rootfs,if=none,cache=none,aio=threads \\
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

# repeat string number
function _repeat () {
    _REPEAT=$1
    while (( ${#_REPEAT} < $2 )) ## Loop until string exceeds desired length
    do
        _REPEAT=$_REPEAT$_REPEAT$_REPEAT # 3 seems to be the optimum number
    done
    _REPEAT=${_REPEAT:0:$2} # Trim to desired length
}

function repeat() {
    _repeat "$@"
    printf "%s\n" "$_REPEAT"
}

function msg () {
    OIFS=$IFS
    IFS=$'\n'
    array=$( printf "%b" "$1" )
    longest=0
    for line in $array;do
        len=${#line}
        [ $len -gt $longest ] && longest=$len
    done
    _repeat "${2:-#}" $(( ${longest} + 6 ))  # $(( ${#1} + 6 ))
    printf '%s\n' "$_REPEAT"
    for line in $array;do 
        printf '%2.2s %b %2.2s\n' " " "$green$line$normal" " "
    done
    printf '%s\n' "$_REPEAT"
    IFS=$OIFS
}

function cpuinfo () {
    msg "This machine cpu info:\n$(lscpu | grep -E '^Thread|^Core|^Socket|^CPU\(')" -
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
        [ "$dir" == "" ] && continue
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
    msg "You can now forward tcp/udp incoming connections to a port on the guest\n\
this allow for example using servers in the guest via the loopback interface\n\
the format is tcp/udp:address:port-:port separated by spaces\n\
Es: tcp:127.0.0.1:5000-:22 udp:127.0.0.1:5001-:23" -

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
    msg  "Select networking:\n\
none = no network at all,\n\
user = uses host networking, can share guest ports on the host network\n\
macvtap = exposed on the host network, does not work on wireless devices" -
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

function display_type () {
    msg "Select graphics, console, normal or sdl with accelleration\n\
SDL NOTE: qemu is not always compiled with sdl, depends on distribution\n\
es: opensuse default to yes while ubuntu does not.\n\
CONSOLE NOTE: Console mode use the terminal as if a serial connection,\n\
if no output is shown append console=ttyS0,115200 to the guest kernel command line\n\
ctrl+c will not terminate the guest.\n\
Use ctrl+a h for help on switching between the console and monitor" -
    while true;do
        read -e -p "Display (console, normal, sdl): " -i "normal" disp
       [[ "$disp" =~ ^console$|^normal$|^sdl$ ]] && break
    done

    case $disp in
        console )
           QEMU="$(sed "s| DISPLAY| $CONSOLE|" <<< "$QEMU")"
           ;; 
        normal )
           QEMU="$(sed "s| DISPLAY| $NORMAL|" <<< "$QEMU")"
           ;; 
        sdl )
           QEMU="$(sed "s| DISPLAY| $ACCELL|" <<< "$QEMU")" 
           ;;
    esac
}

function shared_folder () {
    msg "You can now share a folder between the host and the guest\n\
this works only for linux guests, this script will NOT adjust the folder permissions\n\
to be able to write inside the folder from the guest, you need to chmod 777 the folder\n\
on the host.
to mount the folder inside the guest, as root, type :

mount -t 9p -o trans=virtio,versions=9p2000.L hostshare guest_directory_here" -

    while true;do
        read -ep "Select a folder to share (tab autocomplete): " dir
	[ "$dir" == "" ] && break
        local dir=$(realpath -m "$dir")
        [ -d "$dir" ] && [ -w "$dir" ] && break
        printe "Invalid directory $dir!" 
    done

    case "$dir" in
        "" )
            QEMU="$(sed "/^ *SHARED.*/d" <<< "$QEMU")"
            ;;
        * )
            SHARED="$(sed "s|=FOLDER|=$dir|" <<< "$SHARED")"
            QEMU="$(sed "s| SHARED| $SHARED|" <<< "$QEMU")"
            ;;
    esac
}

function search_bios () {
    OIFS=$IFS
    IFS=$'\n'
    bios=""
    for path in $(qemu-system-x86_64 -L help);do
        [ -d "$path" ] && [ -f "$path/bios.bin" ] && bios="$path/bios.bin" && break
    done
    IFS=$OIFS
    [ "$bios" == "" ] && printk "Bios file not found!" && exit 1
    printk "Found bios.bin in "$path/bios.bin""
    QEMU="$(sed "s| BIOS| $bios|" <<< "$QEMU")"
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

clear

msg "Welcome to $0 $VERSION by $AUTHOR\npress Ctrl+C to exit in any moment" -

read -p "Machine name: " machine

search_bios

iso=$(iso)
drive=$(new_drive $machine)
cpuinfo
sockets=$(readvalue "Cpu sockets: ")
cores=$(readvalue "Cpu cores: ")
threads=$(readvalue "Cpu threads: ")
mem=$(readvalue "Memory size in MB: ")
display_type
network_type
shared_folder

printk "Generating script..."
saveas "$machine.sh"
