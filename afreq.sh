#!/bin/sh

BoostPath=/sys/devices/system/cpu/cpufreq/boost

DutyCycle=5

[ -f "$BoostPath" ] && CanBoost=1

read_file() {
  while read -r FileLine
  do
    printf '%s\n' "$FileLine"
  done < "$1"
}

set_governor() {
  for i in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do 
    currentSetting=$(read_file "$i")
    if [ "$currentSetting" != "$1" ]; then
      [ -z "$DRYRUN" ] &&  printf '%s\n' "$1" > "$i"
      [ "$DBGOUT" = 1 ] && printf 'setting governor %s on cpu %s\n' "$1" "$i"
    else
      [ "$DBGOUT" = 1 ] && printf 'nothing to change on cpu %s\n' "$i"
    fi
  done
}

set_boost() {
  if [ -n "$CanBoost" ]; then
    currentBoost=$(read_file "$BoostPath")
    if [ "$currentBoost" != "$1" ]; then
      [ -z "$DRYRUN" ] &&  printf '%s\n' "$1" > "$BoostPath"
      [ "$DBGOUT" = 1 ] && printf 'setting %s to %s\n' "$1" "$BoostPath"
    else
      [ "$DBGOUT" = 1 ] && printf 'nothing to change on %s\n' "$BoostPath"
    fi
  fi
}

cpupercentage=""

get_cpu_usage() {
  cpupercentage=$((100-$(vmstat 1 2 | tail -1 | awk '{printf "%d\n", $15}')))
}

tick() {

  get_cpu_usage

  # it could be installed or uninstalled during service runtime
  if command -v gamemoded >/dev/null; then
    if LANG=C gamemoded -s | grep -q " active"; then
      gamemodeactive=1
    else
      gamemodeactive=""
    fi
  else
    gamemodeactive=""
  fi

  # set governor if gamemoded is not active
  if [ -z "$gamemodeactive" ]; then
    case "${cpupercentage}" in 
      [1-9]|1[0-9]|20) governor="powersave" ;;
      2[1-9]|[3-5][0-9]|60) governor="performance" ;;
      6[1-9]|[7-9][0-9]|100) governor="schedutil" ;;
    esac

    set_governor "$governor"
  else
    [ "$DBGOUT" = 1 ] && printf 'gamemode active, nothing to do here\n'
  fi

  case "${cpupercentage}" in
    [1-9]|[1-2][0-9]|30)   boostsetting=0 ;;
    3[1-9]|[4-9][0-9]|100) boostsetting=1 ;;
  esac

  set_boost "$boostsetting"
}

outHandler () {
    NO_CONTINUE=1
    [ "$DBGOUT" = 1 ] && printf '\n%s\n' "exiting on signal: $1"
    tick
}

# handle unexpected exits and termination
trap 'outHandler "INT"' INT
trap 'outHandler "TERM"' TERM

## MAIN ##
# input parsing
while [ "$#" -gt 0 ]; do
    case "$1" in
        debug)   DBGOUT=1  ;;
        oneshot) ONESHOT=1 ;;
        dryrun)  DRYRUN=1  ;;
        *)
          printf '%s\n' "${0##*/}: error, invalid argument: ${1}"
          exit 1
          ;;
    esac
    shift
done
[ "$DBGOUT" = 1 ] && printf '%s\n' "${0##*/}"

# do we run as a one shot?
if [ "$ONESHOT" = 1 ]; then
  tick
else
  while [ -z "$NO_CONTINUE" ]; do
    tick
    sleep "$DutyCycle"
  done
fi
