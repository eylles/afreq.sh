#!/bin/sh

get_int_iw() {
    iw dev | awk '$1=="Interface" {print $2}'
}

get_int_wireless_tools() {
    iwgetid | awk '{print $1}'
}

is_command() {
    command -v "$1" >/dev/null 2>&1
}

get_interface() {
    if is_command "iw"; then
        get_int_iw
    elif is_command "iwgetid"; then
        get_int_wireless_tools
    fi
}

get_power_status() {
    iwconfig "$1" 2>/dev/null | awk -F':' '/Power Management/ { print $2 }'
}

set_power_management() {
    interface="$(get_interface)"
    if [ "$1" != "$(get_power_status "$interface")" ];  then
        iwconfig "$interface" power "$1" 2>/dev/null
    fi
}

case "$1" in
    0) set_power_management "on"  ;; # bat
    1) set_power_management "off" ;; # ac
esac
