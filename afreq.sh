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
unset BoostPath AFREQ_NO_CONTINUE DutyCycle WorkCycle ONBATGOV_ST2 ONBATGOV_ST3 ONBATBOOST \
      ONACGOV_ST2 ONACGOV_ST3 ONACBOOST CanBoost DBGOUT DRYRUN DESKTOP

myname="${0##*/}"

BoostPath="/sys/devices/system/cpu/cpufreq/boost"
cpu_paths="/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"

# by default: /etc/default/afreqconfig
CONFIG=/etc/default/afreqconfig
AFREQ_NO_CONTINUE=""
# how many seconds do we tick
DEF_DutyCycle=5
DutyCycle=""
CyclesPerSecond=2
# cycles to tick
WorkCycle=""

# defaults
DEF_ONBATGOV_ST2=40
DEF_ONBATGOV_ST3=70
DEF_ONBATBOOST=35

DEF_ONACGOV_ST2=10
DEF_ONACGOV_ST3=60
DEF_ONACBOOST=25

ONBATGOV_ST2=""
ONBATGOV_ST3=""
ONBATBOOST=""

ONACGOV_ST2=""
ONACGOV_ST3=""
ONACBOOST=""

# empty conf vars
CONF_ac_thresh_ST2=""
CONF_ac_thresh_ST3=""
CONF_ac_thresh_boost=""
CONF_bat_thresh_ST2=""
CONF_bat_thresh_ST3=""
CONF_bat_thresh_boost=""
CONF_interval=""

def_b_stage_1_gov="powersave"
def_b_stage_2_gov="conservative"
def_b_stage_3_gov="performance"

def_a_stage_1_gov="schedutil"
def_a_stage_2_gov="ondemand"
def_a_stage_3_gov="performance"

gov_ac_st1=""
gov_ac_st2=""
gov_ac_st3=""

gov_bat_st1=""
gov_bat_st2=""
gov_bat_st3=""

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

# return the work cycle
# calculated as:
#   DutyCycle * CyclesPerSecond
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
      if is_int "$val" && [ "$val" -gt 0 ] && [ "$val" -le 100 ] ; then
        case "${key}" in
          "AC_THRESH_ST2")     CONF_ac_thresh_ST2="$val" ;;
          "AC_THRESH_ST3")   CONF_ac_thresh_ST3="$val" ;;
          "AC_THRESH_BOOST")   CONF_ac_thresh_boost="$val" ;;
          "BAT_THRESH_ST2")   CONF_bat_thresh_ST2="$val" ;;
          "BAT_THRESH_ST3") CONF_bat_thresh_ST3="$val" ;;
          "BAT_THRESH_BOOST") CONF_bat_thresh_boost="$val" ;;
        esac
      fi
      ;;
    "INTERVAL")
      # check integer type
      if is_int "$val" && [ "$val" -ge 1 ]; then
        CONF_interval="$val"
      fi
      ;;
    *) printf '%s\n' "invalid option ${key}"
  esac
  done < "$1"
  IFS="$old_IFS"
}

set_governor() {
  for i in $cpu_paths; do
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
  # immediate ac state
  im_acstate=""
  if [ -n "${1}" ]; then
    im_acstate=${1}
  fi

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
    if [ -z "$im_acstate" ]; then
      get_ac_state
    else
      [ "$DBGOUT" = 1 ] && printf '%s\n' "using immediate ac state"
    fi
  else
    acstate=1
  fi

  [ "$DBGOUT" = 1 ] && printf '%s\n' "AC state: $acstate"
  if [ "$acstate" = 1 ]; then
    # GovnorST1Thresh="$ONACGOV_ST1"
    GovnorST2Thresh="$ONACGOV_ST2"
    GovnorST3Thresh="$ONACGOV_ST3"
    BoostActive="$ONACBOOST"
    govnorst1="$gov_ac_st1"
    govnorst2="$gov_ac_st2"
    govnorst3="$gov_ac_st3"
  else
    # GovnorST1Thresh="$ONACGOV_ST1"
    GovnorST2Thresh="$ONBATGOV_ST2"
    GovnorST3Thresh="$ONBATGOV_ST3"
    BoostActive="$ONBATBOOST"
    govnorst1="$gov_bat_st1"
    govnorst2="$gov_bat_st2"
    govnorst3="$gov_bat_st3"
  fi

  # set governor if gamemoded is not active
  if [ -z "$gamemodeactive" ]; then
    if pgrep -a perfmod >/dev/null; then
      [ "$DBGOUT" = 1 ] && printf 'perfmod running, setting performance governor\n'
      governor="performance"
    else
      [ "$DBGOUT" = 1 ] && printf '%s\n' "neither gamemode nor perfmod"
      if [ "$cpupercentage" -lt "$GovnorST2Thresh" ]; then
        governor="$govnorst1"
      fi
      if [ "$cpupercentage" -ge "$GovnorST2Thresh" ] && [ "$cpupercentage" -lt "$GovnorST3Thresh" ]; then
        governor="$govnorst2"
      fi
      if [ "$cpupercentage" -ge "$GovnorST3Thresh" ]; then
        governor="$govnorst3"
      fi
    fi
    [ "$DBGOUT" = 1 ] && printf '%s\n' "$governor"
    set_governor "$governor"
  else
    [ "$DBGOUT" = 1 ] && printf 'gamemode active, nothing to do here\n'
  fi

  if [ "$cpupercentage" -lt "$BoostActive" ]; then
    boostsetting="0"
  fi
  if [ "$cpupercentage" -ge "$BoostActive" ]; then
    boostsetting="1"
  fi

  set_boost "$boostsetting"
}

outHandler () {
    [ "$DBGOUT" = 1 ] && printf '\n%s\n' "exiting on signal: $1"
    AFREQ_NO_CONTINUE=1
}

# return type: int
# usage: min value minimum_value
min () {
  if [ "$1" -lt "$2" ]; then
    result="$2"
  else
    result="$1"
  fi
  printf '%d\n' "$result"
}

# return type: int
# usage: max value maximum_value
max () {
  if [ "$1" -gt "$2" ]; then
    result="$2"
  else
    result="$1"
  fi
  printf '%d\n' "$result"
}

loadConf() {
  : # placeholder
  # parse config file if it exists
  if [ -f "$CONFIG" ]; then
    keyval_parse "$CONFIG"
    [ "$DBGOUT" = 1 ] && printf '%s\n' "${myname}: config parsed"
  else
    [ "$DBGOUT" = 1 ] && printf '%s\n' "${myname}: no config, using default values"
  fi

  # fallback to defaults for whatever value wasn't set
  # ac governors
  if [ -z "$CONF_gov_ac_stage_1" ]; then
    gov_ac_st1="$def_a_stage_1_gov"
  else
    gov_ac_st1="$CONF_gov_ac_stage_1"
  fi
  if [ -z "$CONF_gov_ac_stage_2" ]; then
    gov_ac_st2="$def_a_stage_2_gov"
  else
    gov_ac_st2="$CONF_gov_ac_stage_2"
  fi
  if [ -z "$CONF_gov_ac_stage_3" ]; then
    gov_ac_st3="$def_a_stage_3_gov"
  else
    gov_ac_st3="$CONF_gov_ac_stage_3"
  fi

  # battery governors
  if [ -z "$CONF_gov_bat_stage_1" ]; then
    gov_bat_st1="$def_b_stage_1_gov"
  else
    gov_bat_st1="$CONF_gov_bat_stage_1"
  fi
  if [ -z "$CONF_gov_bat_stage_2" ]; then
    gov_bat_st2="$def_b_stage_2_gov"
  else
    gov_bat_st2="$CONF_gov_bat_stage_2"
  fi
  if [ -z "$CONF_gov_bat_stage_3" ]; then
    gov_bat_st3="$def_b_stage_3_gov"
  else
    gov_bat_st3="$CONF_gov_bat_stage_3"
  fi

  # governor stage thresholds ac
  if [ -z "$CONF_ac_thresh_ST2" ]; then
    ONACGOV_ST2=$DEF_ONACGOV_ST2
  else
    ONACGOV_ST2=$CONF_ac_thresh_ST2
  fi
  if [ -z "$CONF_ac_thresh_ST3" ]; then
    ONACGOV_ST3=$DEF_ONACGOV_ST3
  else
    ONACGOV_ST3=$CONF_ac_thresh_ST3
  fi

  # boost threshold ac
  if [ -z "$CONF_ac_thresh_boost" ]; then
    ONACBOOST=$DEF_ONACBOOST
  else
    ONACBOOST=$CONF_ac_thresh_boost
  fi

  # governor stage thresholds bat
  if [ -z "$CONF_bat_thresh_ST2" ]; then
    ONBATGOV_ST2=$DEF_ONBATGOV_ST2
  else
    ONBATGOV_ST2=$CONF_bat_thresh_ST2
  fi
  if [ -z "$CONF_bat_thresh_ST3" ]; then
    ONBATGOV_ST3=$DEF_ONBATGOV_ST3
  else
    ONBATGOV_ST3=$CONF_bat_thresh_ST3
  fi

  # boost threshold bat
  if [ -z "$CONF_bat_thresh_boost" ]; then
    ONBATBOOST=$DEF_ONBATBOOST
  else
    ONBATBOOST=$CONF_bat_thresh_boost
  fi

  # work cycle
  if [ -z "$CONF_interval" ]; then
    DutyCycle=$DEF_DutyCycle
  else
    DutyCycle=$CONF_interval
  fi
  WorkCycle=$(calc_workcycle)

  # ensure no stupid values
  ONBATGOV_ST2=$(min "$ONBATGOV_ST2" 10)
  ONBATGOV_ST2=$(max "$ONBATGOV_ST2" 40)
  ONBATGOV_ST3=$(min "$ONBATGOV_ST3" 60)
  ONBATGOV_ST3=$(max "$ONBATGOV_ST3" 90)
  ONBATBOOST=$(min "$ONBATBOOST" 10)
  ONBATBOOST=$(min "$ONBATBOOST" 90)

  ONACGOV_ST2=$(min "$ONACGOV_ST2" 10)
  ONACGOV_ST2=$(max "$ONACGOV_ST2" 40)
  ONACGOV_ST3=$(min "$ONACGOV_ST3" 60)
  ONACGOV_ST3=$(max "$ONACGOV_ST3" 90)
  ONACBOOST=$(min "$ONACBOOST" 10)
  ONACBOOST=$(min "$ONACBOOST" 90)
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
          printf '%s\n' "${myname}: error, invalid argument: ${1}"
          exit 1
          ;;
    esac
    shift
done
[ "$DBGOUT" = 1 ] && printf '%s\n' "${myname}"

if [ ! -f /sys/class/power_supply/AC/online ]; then
  DESKTOP=1
  [ "$DBGOUT" = 1 ] && printf '%s\n' "${myname}: running on desktop mode"
fi

loadConf

# do we run as a one shot?
if [ "$ONESHOT" = 1 ]; then
  tick
else
  count=0
  tick
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
    if [ -z "$DESKTOP" ]; then
      old_acstate="$acstate"
      get_ac_state
      if [ "$old_acstate" -ne "$acstate" ]; then
        [ "$DBGOUT" = 1 ] && printf '%s\n' "ac state changed before tick!"
        tick "$acstate"
      fi
    else
      acstate=1
    fi
  done
  exit 0
fi
