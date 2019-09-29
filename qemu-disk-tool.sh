#!/bin/bash
# qemu-disk-tool.sh
# bash script to work with qemu disks images via qemu-img
# zizzu 2019

new_disk() {
    if [[ $# != 2 || -z "$1" || -z "$2" ]]; then
        echo "Error usage: $0 new name size"
        exit 1
    fi

    if [[ $2 =~ [a-zA-Z]+ ]];then
        echo "arg 3 must be a number"
        exit 1
    fi

    name="$1"
    name="${name%%.qcow2}.qcow2" # see man bash Parameter Expansion
    
    echo "creating $name size $2G..."
    qemu-img create -f qcow2 "$name" $2G
}

convert_to_raw() {
    if [[ $# != 2 || -z "$1" || -z "$2" ]]; then
        echo "Error usage: $0 convert old.qcow2 new"
        exit 1
    fi
    
    name="$2"
    name="${name%%.raw}.raw"

    echo "converting $1 to $name..."
    qemu-img convert -O raw "$1" "$name"
}

snapshot_create() {
    if [[ $# != 2 || -z "$1" || -z "$2" ]]; then
        echo "Error usage: $0 snapshot snapshot_name filename"
        exit 1
    fi
    qemu-img snapshot -c "$1" "$2"
}

snapshot_delete() {
    if [[ $# != 2 || -z "$1" || -z "$2" ]]; then
        echo "Error usage: $0 delete snapshot_name filename"
        exit 1
    fi
    qemu-img snapshot -d "$1" "$2"
}

snapshot_apply() {
    if [[ $# != 2 || -z "$1" || -z "$2" ]]; then
        echo "Error usage: $0 apply snapshot_name filename"
        exit 1
    fi
    
    read -p "You will lose all changes are you sure?(y/n) " reply
    
    if [[ "$reply" =~ Y|y ]];then
        qemu-img snapshot -a "$1" "$2"
    fi
}

snapshot_list() {
    if [[ $# != 1 || -z "$1" ]]; then
        echo "Error usage: $0 list filename"
        exit 1
    fi
    qemu-img snapshot -l "$1"
}

mount() {
    if [[ $# != 1 || -z "$1" ]]; then
        echo "Error usage: $0 mount filename"
        exit 1
    fi
    sudo modprobe nbd map_part=16
    sudo qemu-nbd -c /dev/nbd0 "$1"
    echo "Partitions are named like /dev/nbd0p1, use mount command to mount them es: mount /dev/nbd0p1 /mnt" 
}

mount_raw_disk() {
    if [[ $# != 1 || -z "$1" ]]; then
        echo "Error usage: $0 mount_raw filename"
        exit 1
    fi
    udisksctl loop-setup --file "$1"
    echo "Partitions are named like /dev/loop0p1, use mount command to mount them es: mount /dev/loop0p1 /mnt"
}

case "$1" in
    new )
        new_disk "$2" "$3"
        ;;
    convert )
	convert_to_raw "$2" "$3"
	;;
    snapshot )
        snapshot_create "$2" "$3"
        ;;
    delete )
        snapshot_delete "$2" "$3"
        ;;
    apply )
        snapshot_apply "$2" "$3"
        ;;
    list )
        snapshot_list "$2"
        ;;
    mount )
	mount "$2"
	;;
    mount_raw )
        mount_raw_disk "$2"
        ;;
    * )
        echo "Usage $0
        new (create a new disk)
	convert (create a raw image from a qcow2 image)
        snapshot (snapshot a disk)
        delete (delete a snapshot of disk)
        apply (apply a snapshot to disk)
        list (list all snapshots for disk)
	mount (mount a qcow2 disk image)
	mount_raw (mount a raw disk image)"
        ;;
esac
