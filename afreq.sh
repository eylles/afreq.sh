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

# battery mode kernel paths

# /proc/sys/kernel/nmi_watchdog
k_watchdog=/proc/sys/kernel/nmi_watchdog
# /proc/sys/vm/dirty_writeback_centisecs
k_writeback=/proc/sys/vm/dirty_writeback_centisecs
# /proc/sys/vm/laptop_mode
k_laptopmode=/proc/sys/vm/laptop_mode

# performance optimization kernel paths

# /proc/sys/vm/nr_hugepages
k_hugepages=/proc/sys/vm/nr_hugepages
# /proc/sys/vm/compaction_proactiveness
k_compaction=/proc/sys/vm/compaction_proactiveness
# /sys/kernel/mm/transparent_hugepage/khugepaged/defrag
k_pagedefrag=/sys/kernel/mm/transparent_hugepage/khugepaged/defrag
# /proc/sys/vm/page_lock_unfairness
k_lock=/proc/sys/vm/page_lock_unfairness

# by default: /etc/default/afreqconfig
DEFCFG=/etc/default/afreqconfig
CONFIG=/etc/afreqconfig
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

# threshold caps
# battery mode

bt_st2_min=10
bt_st2_max=40
bt_st3_min=60
bt_st3_max=90
bt_bst_min=10
bt_bst_max=90

# ac mode

ac_st2_min=10
ac_st2_max=40
ac_st3_min=60
ac_st3_max=90
ac_bst_min=10
ac_bst_max=90

ONBATGOV_ST2=""
ONBATGOV_ST3=""
ONBATBOOST=""
ONBATPERFOPTIM=""

ONACGOV_ST2=""
ONACGOV_ST3=""
ONACBOOST=""
ONACPERFOPTIM=""

# empty conf vars
CONF_ac_thresh_ST2=""
CONF_ac_thresh_ST3=""
CONF_ac_thresh_boost=""
CONF_ac_thresh_optim=""
CONF_bat_thresh_ST2=""
CONF_bat_thresh_ST3=""
CONF_bat_thresh_boost=""
CONF_bat_thresh_optim=""
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

CONF_gov_ac_stage_1=""
CONF_gov_ac_stage_2=""
CONF_gov_ac_stage_3=""

CONF_gov_bat_stage_1=""
CONF_gov_bat_stage_2=""
CONF_gov_bat_stage_3=""

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

# Usage: lstrip "string" "pattern"
lstrip() {
    printf '%s\n' "${1##$2}"
}

# Usage: rstrip "string" "pattern"
rstrip() {
    printf '%s\n' "${1%%$2}"
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
                        "AC_THRESH_ST2")
                            CONF_ac_thresh_ST2="$val"
                            [ "$DBGOUT" = 1 ] && printf '%s\n' \
                                "${myname}: conf ac thresh st2 $CONF_ac_thresh_ST2"
                        ;;
                        "AC_THRESH_ST3")
                            CONF_ac_thresh_ST3="$val"
                            [ "$DBGOUT" = 1 ] && printf '%s\n' \
                                "${myname}: conf ac thresh st3 $CONF_ac_thresh_ST3"
                        ;;
                        "AC_THRESH_BOOST")
                            CONF_ac_thresh_boost="$val"
                            [ "$DBGOUT" = 1 ] && printf '%s\n' \
                                "${myname}: conf ac boost thresh $CONF_ac_thresh_boost"
                        ;;
                        "AC_THRESH_OPTIM")
                            CONF_ac_thresh_optim="$val"
                            [ "$DBGOUT" = 1 ] && printf '%s\n' \
                                "${myname}: conf ac optim thresh $CONF_ac_thresh_optim"
                        ;;
                        "BAT_THRESH_ST2")
                            CONF_bat_thresh_ST2="$val"
                            [ "$DBGOUT" = 1 ] && printf '%s\n' \
                                "${myname}: conf bat thresh st2 $CONF_bat_thresh_ST2"
                        ;;
                        "BAT_THRESH_ST3")
                            CONF_bat_thresh_ST3="$val"
                            [ "$DBGOUT" = 1 ] && printf '%s\n' \
                                "${myname}: conf bat thresh st3 $CONF_bat_thresh_ST3"
                        ;;
                        "BAT_THRESH_BOOST")
                            CONF_bat_thresh_boost="$val"
                            [ "$DBGOUT" = 1 ] && printf '%s\n' \
                                "${myname}: conf bat boost thresh $CONF_bat_thresh_boost"
                        ;;
                        "BAT_THRESH_OPTIM")
                            CONF_bat_thresh_optim="$val"
                            [ "$DBGOUT" = 1 ] && printf '%s\n' \
                                "${myname}: conf bat optim thresh $CONF_bat_thresh_optim"
                        ;;
                    esac
                fi
            ;;
            GOV_*)
                # strip ${val}
                # because someone may want to put the governor string between double quotes
                val=$(lstrip "${val}" "\"")
                val=$(rstrip "${val}" "\"")
                # or single quotes
                val=$(lstrip "${val}" "\'")
                val=$(rstrip "${val}" "\'")
                # if the content of the value for the governor variable is a valid
                # governor
                # default value 0
                is_governor=0
                case "$val" in
                    "powersave")
                        is_governor=1
                    ;;
                    "conservative")
                        is_governor=1
                    ;;
                    "ondemand")
                        is_governor=1
                    ;;
                    "schedutil")
                        is_governor=1
                    ;;
                    "performance")
                        is_governor=1
                    ;;
                    *)
                        is_governor=0
                    ;;
                esac
                if [ "$is_governor" -eq 1 ]; then
                    case "${key}" in
                        "GOV_AC_ST1")
                            CONF_gov_ac_stage_1="$val"
                            [ "$DBGOUT" = 1 ] && printf '%s\n' \
                                "${myname}: conf gov ac st1 $CONF_gov_ac_stage_1"
                        ;;
                        "GOV_AC_ST2")
                            CONF_gov_ac_stage_2="$val"
                            [ "$DBGOUT" = 1 ] && printf '%s\n' \
                                "${myname}: conf gov ac st2 $CONF_gov_ac_stage_2"
                        ;;
                        "GOV_AC_ST3")
                            CONF_gov_ac_stage_3="$val"
                            [ "$DBGOUT" = 1 ] && printf '%s\n' \
                                "${myname}: conf gov ac st3 $CONF_gov_ac_stage_3"
                        ;;
                        "GOV_BAT_ST1")
                            CONF_gov_bat_stage_1="$val"
                            [ "$DBGOUT" = 1 ] && printf '%s\n' \
                                "${myname}: conf gov bat st1 $CONF_gov_bat_stage_1"
                        ;;
                        "GOV_BAT_ST2")
                            CONF_gov_bat_stage_2="$val"
                            [ "$DBGOUT" = 1 ] && printf '%s\n' \
                                "${myname}: conf gov bat st2 $CONF_gov_bat_stage_2"
                        ;;
                        "GOV_BAT_ST3")
                            CONF_gov_bat_stage_3="$val"
                            [ "$DBGOUT" = 1 ] && printf '%s\n' \
                                "${myname}: conf gov bat st3 $CONF_gov_bat_stage_3"
                        ;;
                    esac
                fi
            ;;
            "INTERVAL")
                # check integer type
                if is_int "$val" && [ "$val" -ge 1 ]; then
                    CONF_interval="$val"
                    [ "$DBGOUT" = 1 ] && printf '%s\n' "${myname}: conf interval $CONF_interval"
                fi
                ;;
            *) printf '%s\n' "invalid option ${key}" ;;
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
    cpupercentage=$((100-$(vmstat 1 2 | tail -n 1 | awk '{printf "%d\n", $15}')))
}

acstate=""

get_ac_state() {
    acstate=$(read_file /sys/class/power_supply/AC/online)
}

huge_pages=""
compaction=""
huge_page_defrag=""
lock_unfairness=""
dirty_writeback=""
kernel_watchdog=""

get_vm_vals () {
    # system's huge pages setup
    huge_pages=$(cat "$k_hugepages")
    # set huge pages to 1024
    printf '%d' 1024 > "$k_hugepages"
    compaction=$(cat "$k_compaction")
    huge_page_defrag=$(cat "$k_pagedefrag")
    lock_unfairness=$(cat "$k_lock")
    if [ -z "$DESKTOP" ]; then
        dirty_writeback=$(cat "$k_writeback")
        [ "$DBGOUT" = 1 ] && printf '%s\n' "dirty writeback: $dirty_writeback"
        kernel_watchdog=$(cat "$k_watchdog")
        [ "$DBGOUT" = 1 ] && printf '%s\n' "nmi watchdog: $kernel_watchdog"
    fi
}

bat_optim() {
    if [ "$acstate" -eq 0 ]; then
        printf '%d\n' 0                  > "$k_watchdog"
        printf '%d\n' 1500               > "$k_writeback"
        printf '%d\n' 5                  > "$k_laptopmode"
    else
        printf '%d\n' "$kernel_watchdog" > "$k_watchdog"
        printf '%d\n' "$dirty_writeback" > "$k_writeback"
        printf '%d\n' 0                  > "$k_laptopmode"
    fi
}

perf_optim() {
    case "$1" in
        on)
            printf '%d' 0                     > "$k_compaction"
            printf '%d' 0                     > "$k_pagedefrag"
            printf '%d' 1                     > "$k_lock"
            ;;
        off)
            printf '%d' "$compaction"         > "$k_compaction"
            printf '%d' "$huge_page_defrag"   > "$k_pagedefrag"
            printf '%d' "$lock_unfairness"    > "$k_lock"
            ;;
    esac
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
        bat_optim
    else
        acstate=1
    fi

    [ "$DBGOUT" = 1 ] && printf '%s\n' "AC state: $acstate"
    if [ "$acstate" = 1 ]; then
        # GovnorST1Thresh="$ONACGOV_ST1"
        GovnorST2Thresh="$ONACGOV_ST2"
        GovnorST3Thresh="$ONACGOV_ST3"
        BoostActive="$ONACBOOST"
        OptimActive="$ONACPERFOPTIM"
        govnorst1="$gov_ac_st1"
        govnorst2="$gov_ac_st2"
        govnorst3="$gov_ac_st3"
    else
        # GovnorST1Thresh="$ONACGOV_ST1"
        GovnorST2Thresh="$ONBATGOV_ST2"
        GovnorST3Thresh="$ONBATGOV_ST3"
        BoostActive="$ONBATBOOST"
        OptimActive="$ONBATPERFOPTIM"
        govnorst1="$gov_bat_st1"
        govnorst2="$gov_bat_st2"
        govnorst3="$gov_bat_st3"
    fi

    if [ "$cpupercentage" -lt "$BoostActive" ]; then
        boostsetting="0"
    fi
    if [ "$cpupercentage" -ge "$BoostActive" ]; then
        boostsetting="1"
    fi

    if [ "$cpupercentage" -lt "$OptimActive" ]; then
        optimsetting="off"
    fi
    if [ "$cpupercentage" -ge "$OptimActive" ]; then
        optimsetting="on"
    fi

    # set governor if gamemoded is not active
    if [ -z "$gamemodeactive" ]; then
        if pgrep -a perfmod >/dev/null; then
            [ "$DBGOUT" = 1 ] && printf 'perfmod running, setting performance governor\n'
            governor="performance"
            set_boost 1
            perf_optim "on"
        else
            [ "$DBGOUT" = 1 ] && printf '%s\n' "neither gamemode nor perfmod"
            if [ "$cpupercentage" -lt "$GovnorST2Thresh" ]; then
                governor="$govnorst1"
            fi
            if
                [ "$cpupercentage" -ge "$GovnorST2Thresh" ] &&
                [ "$cpupercentage" -lt "$GovnorST3Thresh" ]
                then
                governor="$govnorst2"
            fi
            if [ "$cpupercentage" -ge "$GovnorST3Thresh" ]; then
                governor="$govnorst3"
            fi
        fi
        [ "$DBGOUT" = 1 ] && printf '%s\n' "$governor"
        set_governor "$governor"
        set_boost "$boostsetting"
        perf_optim "$optimsetting"
    else
        [ "$DBGOUT" = 1 ] && printf 'gamemode active, nothing to do here\n'
        perf_optim "on"
    fi
}

outHandler () {
    [ "$DBGOUT" = 1 ] && printf '\n%s\n' "exiting on signal: $1"
    AFREQ_NO_CONTINUE=1
    # restore defaults on exit
    printf '%d' "$huge_pages"         > "$k_hugepages"
    printf '%d' "$compaction"         > "$k_compaction"
    printf '%d' "$huge_page_defrag"   > "$k_pagedefrag"
    printf '%d' "$lock_unfairness"    > "$k_lock"
    if [ -z "$DESKTOP" ]; then
        printf '%d' "$dirty_writeback" > "$k_writeback"
        printf '%d' "$kernel_watchdog" > "$k_watchdog"
    fi
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
    # parse config file if it exists
    if [ -f "$DEFCFG" ] || [ -f "$CONFIG" ]; then
        # parse the default config if it exists
        if [ -f "$DEFCFG" ]; then
            keyval_parse "$DEFCFG"
            [ "$DBGOUT" = 1 ] && printf '%s\n' "${myname}: default config parsed"
        fi
        # parse the config if it exists, this will write over the default config values
        if [ -f "$CONFIG" ]; then
            keyval_parse "$CONFIG"
            [ "$DBGOUT" = 1 ] && printf '%s\n' "${myname}: config parsed"
        fi
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

    # optim threshold ac
    if [ -z "$CONF_ac_thresh_optim" ]; then
        ONACPERFOPTIM=$ONACBOOST
    else
        ONACPERFOPTIM=$CONF_ac_thresh_optim
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

    # optim threshold bat
    if [ -z "$CONF_bat_thresh_optim" ]; then
        ONBATPERFOPTIM=$ONBATBOOST
    else
        ONBATPERFOPTIM=$CONF_bat_thresh_optim
    fi

    # work cycle
    if [ -z "$CONF_interval" ]; then
        DutyCycle=$DEF_DutyCycle
    else
        DutyCycle=$CONF_interval
    fi
    WorkCycle=$(calc_workcycle)
    [ "$DBGOUT" = 1 ] && printf '%s\n' "work cycle $WorkCycle"

    # ensure no stupid values
    ONBATGOV_ST2=$(min "$ONBATGOV_ST2" "$bt_st2_min")
    ONBATGOV_ST2=$(max "$ONBATGOV_ST2" "$bt_st2_max")
    ONBATGOV_ST3=$(min "$ONBATGOV_ST3" "$bt_st3_min")
    ONBATGOV_ST3=$(max "$ONBATGOV_ST3" "$bt_st3_max")
    ONBATBOOST=$(min "$ONBATBOOST" "$bt_bst_min")
    ONBATBOOST=$(min "$ONBATBOOST" "$bt_bst_max")
    ONBATPERFOPTIM=$(min "$ONBATPERFOPTIM" "$bt_bst_min")
    ONBATPERFOPTIM=$(max "$ONBATPERFOPTIM" "$bt_bst_max")

    ONACGOV_ST2=$(min "$ONACGOV_ST2" "$ac_st2_min")
    ONACGOV_ST2=$(max "$ONACGOV_ST2" "$ac_st2_max")
    ONACGOV_ST3=$(min "$ONACGOV_ST3" "$ac_st3_min")
    ONACGOV_ST3=$(max "$ONACGOV_ST3" "$ac_st3_max")
    ONACBOOST=$(min "$ONACBOOST" "$ac_bst_min")
    ONACBOOST=$(min "$ONACBOOST" "$ac_bst_max")
    ONACPERFOPTIM=$(min "$ONACPERFOPTIM" "$ac_bst_min")
    ONACPERFOPTIM=$(max "$ONACPERFOPTIM" "$ac_bst_max")
}

# handle unexpected exits and termination
trap 'outHandler "INT"' INT
trap 'outHandler "TERM"' TERM
trap 'loadConf' USR1
trap 'loadConf' HUP

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

get_vm_vals

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
