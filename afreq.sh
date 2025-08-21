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
        ONACGOV_ST2 ONACGOV_ST3 ONACBOOST CanBoost DBGOUT DRYRUN DESKTOP ONESHOT


#############
# constants #
#############

myname="${0##*/}"
mypid="$$"

if [ -z "$PIDFILE" ]; then
    PIDFILE=/var/run/acpufreq.pid
fi

BoostPath="/sys/devices/system/cpu/cpufreq/boost"
cpu_paths="/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"

status_path="/var/run/afreq"
status_file="${status_path}/status"

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

############
# defaults #
############

# how many seconds do we tick
DEF_DutyCycle=5
CyclesPerSecond=2

# defaults
DEF_ONBATGOV_ST2=40
DEF_ONBATGOV_ST3=70
DEF_ONBATBOOST=35

DEF_ONACGOV_ST2=10
DEF_ONACGOV_ST3=60
DEF_ONACBOOST=25

def_log_level="0"

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

def_b_stage_1_gov="powersave"
def_b_stage_2_gov="conservative"
def_b_stage_3_gov="performance"

def_a_stage_1_gov="schedutil"
def_a_stage_2_gov="ondemand"
def_a_stage_3_gov="performance"

###########
# globals #
###########

DESKTOP=""

DBGOUT=""
ONESHOT=""
DRYRUN=""

DutyCycle=""
# cycles to tick
WorkCycle=""
AFREQ_NO_CONTINUE=""

ONBATGOV_ST2=""
ONBATGOV_ST3=""
ONBATBOOST=""
ONBATPERFOPTIM=""

ONACGOV_ST2=""
ONACGOV_ST3=""
ONACBOOST=""
ONACPERFOPTIM=""

# type: string
# possible values:
#     0  -  none
#     1  -  info
#     2  -  err
#     3  -  debug
LOG_LEVEL=0

gov_ac_st1=""
gov_ac_st2=""
gov_ac_st3=""

gov_bat_st1=""
gov_bat_st2=""
gov_bat_st3=""

huge_pages=""
compaction=""
huge_page_defrag=""
lock_unfairness=""
dirty_writeback=""
kernel_watchdog=""

cpupercentage=""

acstate=""

CanBoost=""
[ -f "$BoostPath" ] && CanBoost=1

#############
# conf vars #
#############

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
CONF_log_level=""

CONF_gov_ac_stage_1=""
CONF_gov_ac_stage_2=""
CONF_gov_ac_stage_3=""

CONF_gov_bat_stage_1=""
CONF_gov_bat_stage_2=""
CONF_gov_bat_stage_3=""

#############
# functions #
#############

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
    # we want these to match as patterns
    # shellcheck disable=SC2295
    printf '%s\n' "${1##$2}"
}

# Usage: rstrip "string" "pattern"
rstrip() {
    # we want these to match as patterns
    # shellcheck disable=SC2295
    printf '%s\n' "${1%%$2}"
}

# usage: msg_log "level" "message"
# log level can be:
#     info
#     err
#     debug
msg_log () {
    loglevel="$1"
    shift
    message="$*"
    should_log=""
    case "$loglevel" in
        info)
            if [ "$LOG_LEVEL" -gt 0 ]; then
                should_log=1
            fi
            ;;
        err)
            if [ "$LOG_LEVEL" -gt 1 ]; then
                should_log=1
            fi
            ;;
        debug)
            if [ "$LOG_LEVEL" -gt 2 ]; then
                should_log=1
            fi
            ;;
    esac
    [ "$DBGOUT" = 1 ] && printf '%s\n' "$message"
    if [ -n "$should_log" ]; then
        logger -i -t "$myname" -p "daemon.${loglevel}" "$message"
    fi
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
                            msg="conf ac thresh st2 $CONF_ac_thresh_ST2"
                            msg_log "debug" "$msg"
                        ;;
                        "AC_THRESH_ST3")
                            CONF_ac_thresh_ST3="$val"
                            msg="conf ac thresh st3 $CONF_ac_thresh_ST3"
                            msg_log "debug" "$msg"
                        ;;
                        "AC_THRESH_BOOST")
                            CONF_ac_thresh_boost="$val"
                            msg="conf ac boost thresh $CONF_ac_thresh_boost"
                            msg_log "debug" "$msg"
                        ;;
                        "AC_THRESH_OPTIM")
                            CONF_ac_thresh_optim="$val"
                            msg="conf ac optim thresh $CONF_ac_thresh_optim"
                            msg_log "debug" "$msg"
                        ;;
                        "BAT_THRESH_ST2")
                            CONF_bat_thresh_ST2="$val"
                            msg="conf bat thresh st2 $CONF_bat_thresh_ST2"
                            msg_log "debug" "$msg"
                        ;;
                        "BAT_THRESH_ST3")
                            CONF_bat_thresh_ST3="$val"
                            msg="conf bat thresh st3 $CONF_bat_thresh_ST3"
                            msg_log "debug" "$msg"
                        ;;
                        "BAT_THRESH_BOOST")
                            CONF_bat_thresh_boost="$val"
                            msg="conf bat boost thresh $CONF_bat_thresh_boost"
                            msg_log "debug" "$msg"
                        ;;
                        "BAT_THRESH_OPTIM")
                            CONF_bat_thresh_optim="$val"
                            msg="conf bat optim thresh $CONF_bat_thresh_optim"
                            msg_log "debug" "$msg"
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
                            msg="conf gov ac st1 $CONF_gov_ac_stage_1"
                            msg_log "debug" "$msg"
                        ;;
                        "GOV_AC_ST2")
                            CONF_gov_ac_stage_2="$val"
                            msg="conf gov ac st2 $CONF_gov_ac_stage_2"
                            msg_log "debug" "$msg"
                        ;;
                        "GOV_AC_ST3")
                            CONF_gov_ac_stage_3="$val"
                            msg="conf gov ac st3 $CONF_gov_ac_stage_3"
                            msg_log "debug" "$msg"
                        ;;
                        "GOV_BAT_ST1")
                            CONF_gov_bat_stage_1="$val"
                            msg="conf gov bat st1 $CONF_gov_bat_stage_1"
                            msg_log "debug" "$msg"
                        ;;
                        "GOV_BAT_ST2")
                            CONF_gov_bat_stage_2="$val"
                            msg="conf gov bat st2 $CONF_gov_bat_stage_2"
                            msg_log "debug" "$msg"
                        ;;
                        "GOV_BAT_ST3")
                            CONF_gov_bat_stage_3="$val"
                            msg="conf gov bat st3 $CONF_gov_bat_stage_3"
                            msg_log "debug" "$msg"
                        ;;
                    esac
                fi
            ;;
            "INTERVAL")
                # check integer type
                if is_int "$val" && [ "$val" -ge 1 ]; then
                    CONF_interval="$val"
                    msg="conf interval $CONF_interval"
                    msg_log "debug" "$msg"
                fi
                ;;
            "LOG_LEVEL")
                case "${val}" in
                    0|[Nn][Oo][Nn][Ee])
                        CONF_log_level="0"
                        ;;
                    1|[Ii][Nn][Ff][Oo])
                        CONF_log_level="1"
                        ;;
                    2|[Ee][Rr][Rr])
                        CONF_log_level="2"
                        ;;
                    3|[Dd][Ee][Bb][Uu][Gg])
                        CONF_log_level="3"
                        ;;
                esac
                ;;
            *)
                msg="invalid option ${key}"
                msg_log "debug" "$msg"
                ;;
        esac
    done < "$1"
    IFS="$old_IFS"
}

# usage: write_to_file "value" "file"
write_to_file () {
    currcontent=$(head -n 1 "$2" 2>/dev/null)
    if [ "$currcontent" != "$1" ]; then
        msg="writing '$1' to '$2'"
        msg_log "debug" "$msg"
        [ -z "$DRYRUN" ] &&  printf '%s\n' "$1" > "$2"
    fi
}

set_governor() {
    for i in $cpu_paths; do
        currentSetting=$(read_file "$i")
        msg="${i} current governor: ${currentSetting}"
        msg_log "debug" "$msg"
        if [ "$currentSetting" != "$1" ]; then
            write_to_file "$1" "$i"
            msg="${i} setting governor: ${1}"
            msg_log "debug" "$msg"
        else
            msg="${i} governor already: ${1}"
            msg_log "debug" "$msg"
        fi
    done
}

set_boost() {
    if [ -n "$CanBoost" ]; then
        currentBoost=$(read_file "$BoostPath")
        if [ "$currentBoost" != "$1" ]; then
            write_to_file "$1" "$BoostPath"
            msg="${BoostPath} setting: ${1}"
            msg_log "debug" "$msg"
        else
            msg="${BoostPath} already: ${1}"
            msg_log "debug" "$msg"
        fi
    fi
}

get_cpu_usage() {
    cpupercentage=$((100-$(vmstat 1 2 | tail -n 1 | awk '{printf "%d\n", $15}')))
}

get_ac_state() {
    acstate=$(read_file /sys/class/power_supply/AC/online)
}

get_vm_vals () {
    # system's huge pages setup
    huge_pages=$(head "$k_hugepages")
    # set huge pages to 1024
    write_to_file 1024 "$k_hugepages"
    compaction=$(head "$k_compaction")
    huge_page_defrag=$(head "$k_pagedefrag")
    lock_unfairness=$(head "$k_lock")
    if [ -z "$DESKTOP" ]; then
        dirty_writeback=$(head "$k_writeback")
        msg="dirty writeback: $dirty_writeback"
        msg_log "debug" "$msg"
        kernel_watchdog=$(head "$k_watchdog")
        msg="nmi watchdog: $kernel_watchdog"
        msg_log "debug" "$msg"
    fi
}

bat_optim() {
    if [ "$acstate" -eq 0 ]; then
        write_to_file 0                   "$k_watchdog"
        write_to_file 1500                "$k_writeback"
        write_to_file 5                   "$k_laptopmode"
    else
        write_to_file "$kernel_watchdog"  "$k_watchdog"
        write_to_file "$dirty_writeback"  "$k_writeback"
        write_to_file 0                   "$k_laptopmode"
    fi
}

perf_optim() {
    case "$1" in
        on)
            write_to_file 0                      "$k_compaction"
            write_to_file 0                      "$k_pagedefrag"
            write_to_file 1                      "$k_lock"
            ;;
        off)
            write_to_file "$compaction"          "$k_compaction"
            write_to_file "$huge_page_defrag"    "$k_pagedefrag"
            write_to_file "$lock_unfairness"     "$k_lock"
            ;;
    esac
}

print_status () {
    cpu_d_paths="/sys/devices/system/cpu/cpu*"

    cpu_f_path="/sys/devices/system/cpu/cpu0/cpufreq"

    date +"[%Y-%m-%d %H:%M:%S]"
    printf '%s %s: %s\n\n' "$myname" "pid" "$mypid"
    if [ -n "$CanBoost" ]; then
        boost_state=$(head "$BoostPath")
        boost_status=""
        case "$boost_state" in
            0)
                boost_status="off"
                ;;
            1)
                boost_status="on"
                ;;
        esac

        printf '%8s: %s\n' "Boost" "$boost_status"
    fi

    govnor=$(head "${cpu_f_path}/scaling_governor")

    printf '%8s: %s\n' "Governor" "$govnor"

    printf '\n'

    min=$(head "${cpu_f_path}/scaling_min_freq")
    printf '%s %s\n' "CPU min freq" "$min Hz"

    max=$(head "${cpu_f_path}/scaling_max_freq")
    printf '%s %s\n' "CPU max freq" "$max Hz"

    printf '\n'

    printf '%8s: %12s\n' "CPU" "Frequecy"
    for cpu in $cpu_d_paths; do
        frqpath="${cpu}/cpufreq/scaling_cur_freq"
        if [ -r "$frqpath" ]; then
            freq=$(head "$frqpath")
            indx=${cpu##*/}
            printf '%8s: %12s\n' "$indx" "${freq} Hz"
        fi
    done

    printf '\n'

    avg_load=$(awk '{print $1}' /proc/loadavg)
    printf '%s: %s\n' "Average system load" "$avg_load"
    printf '%s: %s\n' "Average CPU percentage" "${cpupercentage}%"

    if [ -z "$DESKTOP" ]; then
        acstatus=""
        case "$acstate" in
            0)
                acstatus="disconnected"
                ;;
            1)
                acstatus="connected"
                ;;
        esac
        printf '%s: %s\n' "AC status" "$acstatus"
    fi
}

write_stats () {
    if [ -z "$DRYRUN" ]; then
        msg="writing status to '${status_file}'"
        msg_log "debug" "$msg"
        if [ ! -d "$status_path" ]; then
            mkdir -p "$status_path"
            : > "$status_file"
        fi
        print_status > "$status_file"
    else
        print_status
    fi

}

tick() {
    msg="setting optimization"
    msg_log "info" "$msg"
    # immediate ac state
    im_acstate=""
    if [ -n "${1}" ]; then
        im_acstate=${1}
    fi

    get_cpu_usage
    msg="cpu percentage: ${cpupercentage}%"
    msg_log "debug" "$msg"

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
            msg="using immediate ac state"
            msg_log "debug" "$msg"
        fi
        bat_optim
    else
        acstate=1
    fi

    msg="AC state: $acstate"
    msg_log "debug" "$msg"
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
            msg="perfmod running, setting performance governor"
            msg_log "debug" "$msg"
            governor="performance"
            boostsetting="1"
            optimsetting="on"
        else
            msg="neither gamemode nor perfmod"
            msg_log "debug" "$msg"
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
        msg="governor: $governor"
        msg_log "debug" "$msg"
        set_governor "$governor"
        set_boost "$boostsetting"
        perf_optim "$optimsetting"
    else
        msg="gamemode active, nothing to do here"
        msg_log "debug" "$msg"
        perf_optim "on"
    fi
    write_stats
}

outHandler () {
    msg="exiting on signal: $1"
    msg_log "debug" "$msg"
    AFREQ_NO_CONTINUE=1
    # restore defaults on exit
    write_to_file "$huge_pages"          "$k_hugepages"
    write_to_file "$compaction"          "$k_compaction"
    write_to_file "$huge_page_defrag"    "$k_pagedefrag"
    write_to_file "$lock_unfairness"     "$k_lock"
    if [ -z "$DESKTOP" ]; then
        write_to_file "$dirty_writeback"  "$k_writeback"
        write_to_file "$kernel_watchdog"  "$k_watchdog"
    fi
    if [ -d "$status_path" ]; then
        rm -rf "$status_path"
    fi
    if [ -f "$PIDFILE" ]; then
        rm "$PIDFILE"
    fi
}

# return type: int
# usage: min_cap value minimum_value
# description: prevents the value from
#     being lower than the minimum_value.
min_cap () {
    if [ "$1" -lt "$2" ]; then
        result="$2"
    else
        result="$1"
    fi
    printf '%d\n' "$result"
}

# return type: int
# usage: max_cap value maximum_value
# description: prevents the value from
#     being higher than the maximum_value.
max_cap () {
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
            msg="default config parsed"
            msg_log "debug" "$msg"
        fi
        # parse the config if it exists, this will write over the default config values
        if [ -f "$CONFIG" ]; then
            keyval_parse "$CONFIG"
            msg="config parsed"
            msg_log "debug" "$msg"
        fi
    else
        msg="no config, using default values"
        msg_log "debug" "$msg"
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

    # log level
    if [ -z "$CONF_log_level" ]; then
        LOG_LEVEL="$def_log_level"
    else
        LOG_LEVEL="$CONF_log_level"
    fi

    # work cycle
    if [ -z "$CONF_interval" ]; then
        DutyCycle=$DEF_DutyCycle
    else
        DutyCycle=$CONF_interval
    fi
    WorkCycle=$(calc_workcycle)
    msg="work cycle $WorkCycle"
    msg_log "debug" "$msg"

    # ensure no stupid values
    ONBATGOV_ST2=$(min_cap "$ONBATGOV_ST2" "$bt_st2_min")
    ONBATGOV_ST2=$(max_cap "$ONBATGOV_ST2" "$bt_st2_max")
    ONBATGOV_ST3=$(min_cap "$ONBATGOV_ST3" "$bt_st3_min")
    ONBATGOV_ST3=$(max_cap "$ONBATGOV_ST3" "$bt_st3_max")
    ONBATBOOST=$(min_cap "$ONBATBOOST" "$bt_bst_min")
    ONBATBOOST=$(min_cap "$ONBATBOOST" "$bt_bst_max")
    ONBATPERFOPTIM=$(min_cap "$ONBATPERFOPTIM" "$bt_bst_min")
    ONBATPERFOPTIM=$(max_cap "$ONBATPERFOPTIM" "$bt_bst_max")

    ONACGOV_ST2=$(min_cap "$ONACGOV_ST2" "$ac_st2_min")
    ONACGOV_ST2=$(max_cap "$ONACGOV_ST2" "$ac_st2_max")
    ONACGOV_ST3=$(min_cap "$ONACGOV_ST3" "$ac_st3_min")
    ONACGOV_ST3=$(max_cap "$ONACGOV_ST3" "$ac_st3_max")
    ONACBOOST=$(min_cap "$ONACBOOST" "$ac_bst_min")
    ONACBOOST=$(min_cap "$ONACBOOST" "$ac_bst_max")
    ONACPERFOPTIM=$(min_cap "$ONACPERFOPTIM" "$ac_bst_min")
    ONACPERFOPTIM=$(max_cap "$ONACPERFOPTIM" "$ac_bst_max")
}

write_pidfile () {
    if [ ! -r "$PIDFILE" ]; then
        msg="pidfile not present, creating it."
        msg_log "info" "$msg"
    fi
    write_to_file "$mypid" "$PIDFILE"
}

# handle unexpected exits and termination
trap 'outHandler INT' INT
trap 'outHandler TERM' TERM
trap 'outHandler USR2' USR2
trap 'outHandler EXIT' EXIT
# handle config reloads
trap 'loadConf' USR1
trap 'loadConf' HUP

## MAIN ##
# input parsing
while [ "$#" -gt 0 ]; do
    case "$1" in
        debug)   DBGOUT=1  ;;
        oneshot) ONESHOT=1 ;;
        dryrun)  DRYRUN=1  ;;
        pidfile|--pidfile) PIDFILE="$1" ;;
        *)
            printf '%s\n' "${myname}: error, invalid argument: ${1}"
            exit 1
        ;;
    esac
    shift
done

loadConf

[ "$DBGOUT" = 1 ] && printf '%s\n' "${myname}"

if [ ! -f /sys/class/power_supply/AC/online ]; then
    DESKTOP=1
    acstate=1
    msg="running on desktop mode"
    msg_log "info" "$msg"
else
    acstate=0
fi

get_vm_vals

# do we run as a one shot?
if [ -n "$ONESHOT" ]; then
    tick
else
    count=0
    pidfile_dir="${PIDFILE%/*}"
    # hopefully this is not needed...
    if [ ! -d "$pidfile_dir" ]; then
        [ -z "$DRYRUN" ] && mkdir -p "$pidfile_dir"
    fi
    write_pidfile
    while [ -z "$AFREQ_NO_CONTINUE" ]; do
        if [ -n "$AFREQ_NO_CONTINUE" ]; then
            exit 0
        fi
        if [ "$count" -eq "$WorkCycle" ]; then
            tick
            # may as well while we are running...
            write_pidfile
            count=0
        else
            count=$(( count + 1 ))
        fi
        sleep 0.5
        if [ -z "$DESKTOP" ]; then
            old_acstate="$acstate"
            get_ac_state
            if [ "$old_acstate" -ne "$acstate" ]; then
                msg="ac state changed before tick"
                msg_log "info" "$msg"
                tick "$acstate"
            fi
        else
            acstate=1
        fi
    done
fi
