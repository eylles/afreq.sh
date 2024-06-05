#!/bin/sh

# PATH should only include /usr/* if it runs after the mountnfs.sh
# script.  Scripts running before mountnfs.sh should remove the /usr/*
# entries.
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# naming schemes:
# functions: all function names are lowercase and use dashes "_" to separate words
# RUNVARS: these are variables that directly affect the running of the program and are rarely
# modified after being set, they are all in UPPERCASE and if separated it is done with dashes "_"
# FuncVars: these variables are set and modified by various methods through the program ticks, they
# are composed of at least 2 words and each composing word starts with a capital letter.
# CONF_vars: variables to be set by the config file if this exist, these will have an UPPERCASE
# prefix followed by a dash, and then the rest of the name has a uppercase letter followed by
# lowercase letters, the prefixes can be "DEF_" for default values set inside the program, "CONF_"
# for values obtained from the config file, and finally "USE_" for the value that will be actually
# used by the program

# unset variables
unset BoostPath AFREQ_NO_CONTINUE DutyCycle WorkCycle ONBATGOV_PERF ONBATGOV_SCHED ONBATBOOST \
      ONACGOV_PERF ONACGOV_SCHED ONACBOOST CanBoost DBGOUT DRYRUN DESKTOP

BoostPath=/sys/devices/system/cpu/cpufreq/boost

AFREQ_NO_CONTINUE=""
# how many seconds do we tick
DutyCycle=5
CyclesPerSecond=2
WorkCycle=""

# defaults
ONBATGOV_PERF=40
ONBATGOV_SCHED=70
ONBATBOOST=35

ONACGOV_PERF=10
ONACGOV_SCHED=60
ONACBOOST=25

# empty conf vars
CONF_ac_thresh_perf=""
CONF_ac_thresh_sched=""
CONF_ac_thresh_boost=""
CONF_bat_thresh_perf=""
CONF_bat_thresh_sched=""
CONF_bat_thresh_boost=""
CONF_interval=""

[ -f "$BoostPath" ] && CanBoost=1

read_file() {
  while read -r FileLine
  do
    printf '%s\n' "$FileLine"
  done < "$1"
}

# usage: is_int "number"
is_int() {
  printf %d "$1" >/dev/null 2>&1
}

calc_workcycle() {
  #WorkCycle
  result=$(( DutyCycle * CyclesPerSecond ))
  printf '%d\n' $result
}

keyval_parse() {
  old_IFS="$IFS"
  # Setting 'IFS' tells 'read' where to split the string.
  while IFS='=' read -r key val; do
  # Skip over lines containing comments.
  # (Lines starting with '#').
  [ "${key##\#*}" ] || continue
  # '$key' stores the key.
  # '$val' stores the value.
  # validate type
  case "${key}" in
    *THRESH*)
      # check integer type for thresholds
      if is_int "$val"; then
        case "${key}" in
          "AC_THRESH_PERF")     CONF_ac_thresh_perf="$val" ;;
          "AC_THRESH_SCHED")   CONF_ac_thresh_sched="$val" ;;
          "AC_THRESH_BOOST")   CONF_ac_thresh_boost="$val" ;;
          "BAT_THRESH_PERF")   CONF_bat_thresh_perf="$val" ;;
          "BAT_THRESH_SCHED") CONF_bat_thresh_sched="$val" ;;
          "BAT_THRESH_BOOST") CONF_bat_thresh_boost="$val" ;;
          "INTERVAL") CONF_interval="$val" ;;
        esac
      fi
      ;;
    *) printf '%s\n' "invalid option ${key}"
  esac
  done < "$1"
  IFS="$old_IFS"
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
    [ "$DBGOUT" = 1 ] && printf '\n%s\n' "exiting on signal: $1"
    AFREQ_NO_CONTINUE=1
}

loadConf() {
  : # placeholder
}

# handle unexpected exits and termination
trap 'outHandler "INT"' INT
trap 'outHandler "TERM"' TERM
trap 'loadConf' USR1

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
  WorkCycle=$(calc_workcycle)
  AFREQ_NO_CONTINUE=""
  while [ -z "$AFREQ_NO_CONTINUE" ]; do
    if [ -n "$AFREQ_NO_CONTINUE" ]; then
      exit 0
    fi
    if [ "$count" -eq "$WorkCycle" ]; then
      tick
      count=0
    else
      count=$(( count + 1 ))
    fi
    sleep 0.5
  done
  exit 0
fi
