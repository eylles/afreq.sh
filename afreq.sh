#!/bin/sh

BoostPath=/sys/devices/system/cpu/cpufreq/boost

DutyCycle=5
WorkCycle=$(( DutyCycle * 2 ))

ONBATGOV_PERF=40
ONBATGOV_SCHED=70
ONBATBOOST=35

ONACGOV_PERF=10
ONACGOV_SCHED=60
ONACBOOST=25

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
      [ "$DBGOUT" = 1 ] && printf '%s current governor: %s\n' "$i" "$currentSetting"
    if [ "$currentSetting" != "$1" ]; then
      [ -z "$DRYRUN" ] &&  printf '%s\n' "$1" > "$i"
      [ "$DBGOUT" = 1 ] && printf '%s setting governor: %s\n' "$i" "$1"
    else
      [ "$DBGOUT" = 1 ] && printf '%s governor already: %s\n' "$i" "$1"
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
      [ "$DBGOUT" = 1 ] && printf '%s already: %s\n' "$BoostPath" "$1"
    fi
  fi
}

cpupercentage=""

get_cpu_usage() {
  cpupercentage=$((100-$(vmstat 1 2 | tail -1 | awk '{printf "%d\n", $15}')))
}

acstate=""

get_ac_state() {
  acstate=$(read_file /sys/class/power_supply/AC/online)
}

tick() {

  get_cpu_usage
  [ "$DBGOUT" = 1 ] && printf '%s\n' "cpu percentage: ${cpupercentage}%"

  # it could be installed or uninstalled during service runtime
  if command -v gamemoded >/dev/null; then
    if pgrep -f gamemoderun >/dev/null; then
      gamemodeactive=1
    else
      gamemodeactive=""
    fi
  else
    gamemodeactive=""
  fi

  if [ -z "$DESKTOP" ]; then
    get_ac_state
  else
    acstate=1
  fi

  [ "$DBGOUT" = 1 ] && printf '%s\n' "AC state: $acstate"
  if [ "$acstate" = 1 ]; then
    GovnorPerf="$ONACGOV_PERF"
    GovnorScd="$ONACGOV_SCHED"
    BoostActiv="$ONACBOOST"
  else
    GovnorPerf="$ONBATGOV_PERF"
    GovnorScd="$ONBATGOV_SCHED"
    BoostActiv="$ONBATBOOST"
  fi

  # set governor if gamemoded is not active
  if [ -z "$gamemodeactive" ]; then
    if pgrep -a perfmod >/dev/null; then
      [ "$DBGOUT" = 1 ] && printf 'perfmod running, setting performance governor\n'
      governor="performance"
    else
      [ "$DBGOUT" = 1 ] && printf '%s\n' "neither gamemode nor perfmod"
      if [ "$cpupercentage" -lt "$GovnorPerf" ]; then
        governor="powersave"
      fi
      if [ "$cpupercentage" -ge "$GovnorPerf" ] && [ "$cpupercentage" -lt "$GovnorScd" ]; then
        governor="performance"
      fi
      if [ "$cpupercentage" -ge "$GovnorScd" ]; then
        governor="schedutil"
      fi
    fi
    [ "$DBGOUT" = 1 ] && printf '%s\n' "$governor"
    set_governor "$governor"
  else
    [ "$DBGOUT" = 1 ] && printf 'gamemode active, nothing to do here\n'
  fi

  if [ "$cpupercentage" -lt "$BoostActiv" ]; then
    boostsetting="0"
  fi
  if [ "$cpupercentage" -ge "$BoostActiv" ]; then
    boostsetting="1"
  fi

  set_boost "$boostsetting"
}

outHandler () {
    NO_CONTINUE=1
    [ "$DBGOUT" = 1 ] && printf '\n%s\n' "exiting on signal: $1"
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

if [ ! -f /sys/class/power_supply/AC/online ]; then
  DESKTOP=1
  [ "$DBGOUT" = 1 ] && printf '%s\n' "${0##*/}: running on desktop mode"
fi

# do we run as a one shot?
if [ "$ONESHOT" = 1 ]; then
  tick
else
  count=0
  tick
  while [ -z "$NO_CONTINUE" ]; do
    if [ "$count" -eq "$WorkCycle" ]; then
      tick
      count=0
    else
      count=$(( count + 1 ))
    fi
    sleep 0.5
  done
fi
