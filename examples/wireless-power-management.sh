#!/bin/sh

get_power_status() {
    iwconfig wlan0 2>/dev/null | awk -F':' '/Power Management/ { print $2 }'
}

set_power_management() {
    if [ "$1" != "$(get_power_status)" ];  then
        iwconfig wlan0 power "$1" 2>/dev/null
    fi
}

case "$1" in
    0) set_power_management "on"  ;; # bat
    1) set_power_management "off" ;; # ac
esac
