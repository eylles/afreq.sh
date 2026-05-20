#!/bin/sh

interface=""
# Find the first wireless interface via sysfs (Zero forks)
# Most laptops only have one, e.g., wlan0
for dev in /sys/class/net/*; do
    if [ -d "$dev/wireless" ] || [ -d "$dev/phy80211" ]; then
        interface="${dev##*/}"
        break
    fi
    unset dev
done

# If no interface found, exit silently
[ -z "$interface" ] && exit 0

get_power_status() {
    if iwconfig "$1" 2>/dev/null | grep -q "Power Management:on"; then
        echo "on"
    else
        echo "off"
    fi
}

case "$(get_power_status "$interface")" in
    on)
        iwconfig "$interface" power off
        ;;
esac
