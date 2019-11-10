#!/bin/bash
# Script to select default sound card to use with pulseserver and volume % in a human readable way.

# Copyright (c) 2019 zizzu.
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

function get_sinks() {
sinks=$(pacmd list-sinks | awk '
/index/{ 
    ind=$0;
    getline;
    res=ind $0;
    while(getline tmp) {
        if(tmp ~ ".*alsa.name.*") {
            res=res tmp
        }
        if(tmp ~ ".*alsa.card_name.*") {
            res=res tmp
            break;
        }
    }
    res = gensub(".*(* index: [0-9]+|  index: [0-9]+).*name: (\\S+).*alsa.name = (\".*\").*alsa.card.name = (\".*\")", "\\1 - \\2 \\3 \\4", "g", res);
    printf "%s\n", res;
}')

echo "$sinks"
}

function print_sinks() {
    IFS=$'\n'
    for s in $1
    do  
        echo "$s"
    done
}

function isdigit() {
    if [[ $1 =~ ^[0-9]+$ ]]
    then
        return 1
    fi

    return 0
}

function usage() {
    echo -e "Usage $0\n\t-l\t\tlist sinks\n\t-s index\tset default sink\n\t-v 0-100\tset current sink volume 0-100"
    exit 1
}

sinks=$(get_sinks)

if [ "$1" == "-l" ]
then
    print_sinks  "$sinks"
    exit 0
fi

if [ "$1" == "-s" ] && [ $# == 2 ]
then
    ! isdigit $2 || usage
    pacmd set-default-sink $2
    exit 0
fi

if [ "$1" == "-v" ] && [ $# == 2 ]
then
    ! isdigit $2 || usage
    ! ( [ $2 -lt 0 ] || [ $2 -gt 100 ] ) || usage
    currsink=$(pacmd list-sinks | awk '/^ +\*/{ print $3}')
    pacmd set-sink-volume $currsink $(( 65536*$2/100 ))
    exit 0
fi

usage
