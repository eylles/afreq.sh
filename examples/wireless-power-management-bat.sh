#!/bin/sh

get_power_status() {
    iwconfig wlan0 | awk -F':' '/Power Management/ { print $2 }'
}

case "$(get_power_status)" in
    off)
        iwconfig wlan0 power on
        ;;
esac
