#!/bin/sh

# PATH should only include /usr/* if it runs after the mountnfs.sh
# script.  Scripts running before mountnfs.sh should remove the /usr/*
# entries.
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# naming schemes:
# functions: all function names are lowercase and use underscores "_" to separate words.
# RUNVARS: these are variables that directly affect the running of the program and are rarely
# modified after being set, they are constants by all means except not being prefixed by readonly
# they are all in UPPERCASE and if separated it is done with underscores "_"
# FuncVars: these variables are set and modified by various methods through the program ticks, they
# are composed of at least 2 words and each composing word starts with a capital letter.
# CONF_vars: variables to be set by the config file if this exist, these will have an UPPERCASE
# prefix followed by undrescore, and then the rest of the name is lowercase, the prefixes can be
# "DEF_" for default values set inside the program, "CONF_" for values obtained from the config file
# and finally "USE_" for the value that will be actually used by the program

# unset variables
unset BoostPath AFREQ_NO_CONTINUE DutyCycle WorkCycle ONBATGOV_ST2 ONBATGOV_ST3 ONBATBOOST \
        ONACGOV_ST2 ONACGOV_ST3 ONACBOOST DBGOUT DRYRUN DESKTOP ONESHOT


#############
# constants #
#############

myname="${0##*/}"
mypid="$$"

version="@VERSION@"

if [ -z "$PIDFILE" ]; then
    PIDFILE=/var/run/acpufreq.pid
fi

BoostPath=""
# /sys/devices/system/cpu/intel_pstate/no_turbo
IntelNoTurbo="/sys/devices/system/cpu/intel_pstate/no_turbo"
IntelPstatus="/sys/devices/system/cpu/intel_pstate/status"
# /sys/devices/system/cpu/cpufreq/boost
CpuFreqBoost="/sys/devices/system/cpu/cpufreq/boost"
CPU_BASE_PATH="/sys/devices/system/cpu"
CPU_DEVS="${CPU_BASE_PATH}/cpu*/cpufreq"
cpu_f_path="${CPU_BASE_PATH}/cpu0/cpufreq"
ac_adapter_path="/sys/class/power_supply"

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

interval_max=600

PollMsMin=100
PollMsMax=5000

# how many ticks to consider the settings stable and increase PollMs
StableThreshold=5

PollMsStep=100

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

PollMs=500

StableCount=0

gamemode_old=0
governor_old=""
boost_old=""

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

CPUfreqDriver=""
if [ -f "$CpuFreqBoost" ]; then
    CPUfreqDriver="cpufreq"
    BoostPath="$CpuFreqBoost"
fi
if [ -f "$IntelNoTurbo" ]; then
    CPUfreqDriver="intelturbo"
    BoostPath="$IntelNoTurbo"
fi

has_usleep=""
has_usleep=$(command -v usleep)
[ -z "$has_usleep" ] && has_usleep=$(command -v busybox)

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

# usage: is_int "number"
# return type: bool
is_int () {
    printf %d "$1" >/dev/null 2>&1
}

# usage: lstrip "string" "pattern"
# description: remove patter from start of string
# return type: string
lstrip () {
    # we want these to match as patterns
    # shellcheck disable=SC2295
    printf '%s\n' "${1##$2}"
}

# usage: rstrip "string" "pattern"
# description: remove patter from end of string
# return type: string
rstrip () {
    # we want these to match as patterns
    # shellcheck disable=SC2295
    printf '%s\n' "${1%%$2}"
}

# usage: msg_log "level" "message"
# description: log passed message according to LOG_LEVEL variable
# log level can be:
#     info
#     err
#     debug
# return type: void
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

# usage: calc_workcycle
# return the work cycle
# calculated as:
#   DutyCycle * CyclesPerSecond
# return type: int
calc_workcycle () {
    #WorkCycle
    result=$(( DutyCycle * CyclesPerSecond ))
    printf '%d\n' $result
}

# usage: keyval_parse CONF_FILE
# description: parse passed conf file and assign values of CONF_ prefix vars
# return type: void
keyval_parse () {
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
# description: write value to file only if it is different from file's current value
#     if the passed value is "--" then read value from stdin
#     only write_stats is ever going to use this so we can do special handling
# return type: void
write_to_file () {
    stdin_val=""
    file="$2"
    filedir="${file%/*}"
    value="$1"
    can_w=""
    if [ "$value" = "--" ]; then
        stdin_val=1
        value=$(cat)
        a_value=$(printf '%s\n' "$value" | awk '/Boost/||/Governor/||/AC/{print$0}')
    fi
    if [ -e "$file" ] && [ -w "$file" ]; then
        if [ -z "$stdin_val" ]; then
            currcontent=$(head -n 1 "$file" 2>/dev/null)
            if [ "$currcontent" != "$value" ]; then
                can_w=1
            fi
        else
            currcontent=$(awk '/Boost/||/Governor/||/AC/{print$0}' "$file")
            if [ "$currcontent" != "$a_value" ]; then
                can_w=1
            fi
        fi
    elif [ -e "$filedir" ] && [ -w "$filedir" ]; then
        can_w=1
    else
        msg="cannot write to file $file"
        msg_log "err" "$msg"
    fi
    if [ -n "$can_w" ]; then
        msg="writing '$value' to '$file'"
        msg_log "debug" "$msg"
        [ -z "$DRYRUN" ] &&  printf '%s\n' "$value" > "$file"
    fi

}

# usage: set_governor "governor"
# description: sets cpu governor to all available cpus
# return type: void
set_governor () {
    for i in ${CPU_DEVS}; do
        dev="${i}/scaling_governor"
        # msg_log "debug" "opening: $dev"
        currentSetting=$(head -n 1 "$dev")
        msg="'${dev}' current governor: ${currentSetting}"
        msg_log "debug" "$msg"
        if [ "$currentSetting" != "$1" ]; then
            write_to_file "$1" "$dev"
            msg="${dev} setting governor: ${1}"
            msg_log "debug" "$msg"
        else
            msg="${dev} governor already: ${1}"
            msg_log "debug" "$msg"
        fi
    done
}

# usage: set_intelnoturbo "setting"
# setting: on | off
# description: set the value of the intel_pstate driver turbo boost switch
# return type: void
set_intelnoturbo () {
    case "$1" in
        on)
            write_to_file 0 "$IntelNoTurbo"
            ;;
        off)
            write_to_file 1 "$IntelNoTurbo"
            ;;
    esac
}

# usage: set_cpufreqboost "setting"
# setting: on | off
# description: set the value of the cpufreq driver turbo boost switch
# return type: void
set_cpufreqboost () {
    case "$1" in
        on)
            write_to_file 1 "$CpuFreqBoost"
            ;;
        off)
            write_to_file 0 "$CpuFreqBoost"
            ;;
    esac
}

# usage: set_boost "setting"
# setting: on | off
# description: set the value of turbo boost if the cpu frequency scaling driver supports turbo boost
# return type: void
set_boost () {
    if [ -n "$BoostPath" ]; then
        msg="${BoostPath} setting: ${1}"
        msg_log "debug" "$msg"
        case "$CPUfreqDriver" in
            cpufreq)
                set_cpufreqboost "$1"
                ;;
            intelturbo)
                set_intelnoturbo "$1"
                ;;
        esac
    fi
}

# usage: get_governor
# description: get the value of the current cpu scaling governor
# return type: string
# caveats: this only gets the value for the cpu0, cpu cores are expected to have the same value
get_governor () {
    head -n 1 "${cpu_f_path}/scaling_governor"
}

# usage: get_intelnoturbo
# description: set the value of the intel_pstate driver turbo boost switch
# return type: string
# return values: on | off
get_intelnoturbo () {
    case $(head "$IntelNoTurbo") in
        0)
            printf '%s\n' "on"
            ;;
        1)
            printf '%s\n' "off"
            ;;
    esac
}

# usage: get_cpufreqboost
# description: get the turbo boost value from the cpufreq driver
# return type: string
# return values: on | off
get_cpufreqboost () {
    case $(head "$CpuFreqBoost") in
        1)
            printf '%s\n' "on"
            ;;
        0)
            printf '%s\n' "off"
            ;;
    esac
}

# usage: get_boost
# description: get the value of turbo boost from the supported cpu frequency scaling driver
# return type: string
# return values: on | off
get_boost () {
    case "$CPUfreqDriver" in
        cpufreq)
            get_cpufreqboost
            ;;
        intelturbo)
            get_intelnoturbo
            ;;
    esac
}

# usage: get_cpu_usage
# description: calculate a snapshot of the current cpu usage and store it to cpupercentage
# return type: void
get_cpu_usage () {
    cpupercentage=$((100-$(vmstat 1 2 | tail -n 1 | awk '{printf "%d\n", $15}')))
}

# usage: get_ac_state
# description: get the current ac state and store it to acstate
# return type: void
get_ac_state () {
    if on_ac_power; then
        acstate=1
    else
        acstate=0
    fi
}

# usage: get_vm_vals
# description: fetch values of interfaces in /proc/sys/vm and /proc/sys/kernel
# return type: void
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
    governor_old=$(get_governor)
    boost_old=$(get_boost)
}

# usage: bat_optim
# description: set optimizations for lower power consumption when running on battery
# return type: void
bat_optim () {
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

# usage: perf_optim setting
# setting: on | off
# description: set kernel dials and switches to squeeze some extra performance
# return type: void
perf_optim () {
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

# usage: print_status
# description: output a summary of the daemon's status
# return type: string
print_status () {
    date +"[%Y-%m-%d %H:%M:%S]"
    printf '%8s: %s\n' "$myname" "$mypid"
    printf '%8s: %s\n'  "Version" "$version"
    printf '%8s: %s\n\n' "Driver" "$CPUfreqDriver"

    if [ -n "$BoostPath" ]; then
        boost_status=$(get_boost)
        printf '%8s: %s\n' "Boost" "$boost_status"
    fi

    govnor=$(head "${cpu_f_path}/scaling_governor")
    printf '%8s: %s\n\n' "Governor" "$govnor"

    min=$(head "${cpu_f_path}/scaling_min_freq")
    printf '%s %s\n' "CPU min freq" "$min Hz"

    max=$(head "${cpu_f_path}/scaling_max_freq")
    printf '%s %s\n' "CPU max freq" "$max Hz"

    printf '\n'

    printf '%8s: %12s\n' "CPU" "Frequecy"
    for cpu in $CPU_DEVS; do
        frqpath="${cpu}/scaling_cur_freq"
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

# usage: write_stats
# description: wrapper function to write the status_file
# return type: void
write_stats () {
    if [ -z "$DRYRUN" ]; then
        msg="writing status to '${status_file}'"
        msg_log "debug" "$msg"
        if [ ! -d "$status_path" ]; then
            mkdir -p "$status_path" 2>/dev/null
        fi
        print_status | write_to_file "--" "$status_file"
    else
        print_status
    fi

}

# usage: min_cap value minimum_value
# description: prevents the value from
#     being lower than the minimum_value.
# return type: int
min_cap () {
    if [ "$1" -lt "$2" ]; then
        result="$2"
    else
        result="$1"
    fi
    printf '%d\n' "$result"
}

# usage: max_cap value maximum_value
# description: prevents the value from
#     being higher than the maximum_value.
# return type: int
max_cap () {
    if [ "$1" -gt "$2" ]; then
        result="$2"
    else
        result="$1"
    fi
    printf '%d\n' "$result"
}

# usage: tick
# description: perform fetches of current status, calculate governor stage and setting of, boost,
#     optimizations and call write_stats
# return type: void
tick () {
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
            gamemodeactive=0
        fi
    else
        gamemodeactive=0
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
        boostsetting="off"
    fi
    if [ "$cpupercentage" -ge "$BoostActive" ]; then
        boostsetting="on"
    fi

    if [ "$cpupercentage" -lt "$OptimActive" ]; then
        optimsetting="off"
    fi
    if [ "$cpupercentage" -ge "$OptimActive" ]; then
        optimsetting="on"
    fi

    # set governor if gamemoded is not active
    if [ 0 -eq "$gamemodeactive" ]; then
        if pgrep -a perfmod >/dev/null; then
            msg="perfmod running, setting performance governor"
            msg_log "debug" "$msg"
            governor="performance"
            boostsetting="on"
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
        if [ "$governor" = "$governor_old" ] && [ "$boostsetting" = "$boost_old" ]; then
            StableCount=$(( StableCount + 1 ))
        else
            StableCount=0
            governor_old="$governor"
            boost_old="$boostsetting"
        fi
        msg_log "debug" "Stable Count '$StableCount'"
    else
        msg="gamemode active, nothing to do here"
        msg_log "debug" "$msg"
        perf_optim "on"
        if [ "$gamemodeactive" -eq "$gamemode_old" ]; then
            StableCount=$(( StableCount + 1 ))
        else
            StableCount=0
            gamemode_old="$gamemodeactive"
        fi
    fi
    write_stats
    if [ "$StableCount" -ge "$StableThreshold" ]; then
        PollMs=$(( PollMs + PollMsStep ))
        PollMs=$(max_cap "$PollMs" "$PollMsMax")
        msg_log "debug" "PollMs increased to '$PollMs'"
    elif [ "$StableCount" -eq 0 ]; then
        PollMs=$(( PollMs - PollMsStep ))
        PollMs=$(min_cap "$PollMs" "$PollMsMin")
        msg_log "debug" "PollMs reduced to '$PollMs'"
    else
        msg_log "debug" "PollMs unchanged at '$PollMs' (StableCount=$StableCount)"
    fi
}

# usage: outHandler
# description: restore default kernel tunable values and remove status_file and PIDFILE
# return type: void
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
    if [ -z "$DRYRUN" ] && [ -d "$status_path" ]; then
        rm -rf "$status_path" 2>/dev/null
    fi
    if [ -z "$DRYRUN" ] && [ -f "$PIDFILE" ]; then
        rm -f "$PIDFILE" 2>/dev/null
    fi
}

# usage: loadConf
# description: call keyval_parse on the defined config files, merge CONF and default values,
#     constrain governor stage values within ranges
# return type: void
loadConf () {
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
        DutyCycle=$(max_cap "$CONF_interval" "$interval_max")
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

# usage: write_pidfile
# description: wrapper function to write PIDFILE
# return type: void
write_pidfile () {
    if [ ! -r "$PIDFILE" ]; then
        msg="pidfile not present, creating it."
        msg_log "info" "$msg"
    fi
    write_to_file "$mypid" "$PIDFILE"
}

# usage: is_instance "pid"
# description: check if passed pid is an afreq instance
# return type: bool
is_instance () {
    ps ax -o'pid=,cmd=' \
        | sed 's/^ *//' \
        | awk \
            -v pid="$1" \
            -v name="$myname" \
            '
                BEGIN { found = 0 }
                $1 == pid && $0 ~ name { found = 1 }
                END { if (!found) exit 1 }
            '
}

# usage: msleep int
# description: wrapper function to sleep for the passed amount of milliseconds
# return type: void
msleep () {
    milisecs="$1"
    if [ -n "$has_usleep" ]; then
        microsecs="${milisecs}000"
        case "$has_usleep" in
            */usleep)
                usleep "$microsecs"
                ;;
            */busybox)
                busybox usleep "$microsecs"
                ;;
        esac
    else
        sec_whole=$(( milisecs / 1000 ))
        sec_decim=$(( milisecs % 1000 ))
        sec_decim=$( printf '%03d' $sec_decim)
        secs="${sec_whole}.${sec_decim}"
        sleep "$secs"
    fi
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

DESKTOP=1
acstate=1
if [ -d "$ac_adapter_path" ]; then
    for supply in "$ac_adapter_path"/B* ; do
        if [ -d "$supply" ] && [ -r "${supply}/type" ]; then
            type=$(head -n 1 "${supply}/type")
            case "$type" in
                Battery)
                    DESKTOP=""
                    ;;
            esac
        else
            continue
        fi
    done
    if [ -z "$DESKTOP" ]; then
        get_ac_state
    fi
fi

case "$CPUfreqDriver" in
    intelturbo)
        # make the intel p_state driver set P-states as requested by the generic frequency scaling
        # governors.
        write_to_file "passive" "$IntelPstatus"
        ;;
esac

get_vm_vals
get_cpu_usage

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
    if [ -z "$DRYRUN" ] && [ -r "$PIDFILE" ]; then
        pidfilepid=$(head "$PIDFILE")
        if [ "$mypid" -ne "$pidfilepid" ] && is_instance "$pidfilepid" ;then
            printf '%s\n' "${myname}: an instance is already running with pid $pidfilepid"
            exit 1
        fi
    fi
    write_pidfile
    write_stats
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
        msleep "$PollMs"
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
            msg="running on desktop mode"
            msg_log "info" "$msg"
        fi
    done
fi
