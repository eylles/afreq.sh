#!/bin/sh

interface=""
# Find the first wireless interface via sysfs (Zero forks)
# Most laptops only have one, e.g., wlan0
for dev in /sys/class/net/*; do
    if [ -d "$dev/wireless" ] || [ -d "$dev/phy80211" ]; then
        interface="${dev##*/}"
        break
    fi
done
unset dev

# If no interface found, exit silently
[ -z "$interface" ] && exit 0

get_power_status() {
    status=$(iwconfig "$1" 2>/dev/null)

    case "$status" in
        *"Power Management:on"*)  echo "on" ;;
        *"Power Management:off"*) echo "off" ;;
    esac
}

echo "interface: $interface"
echo "power management: $(get_power_status "$interface")"
