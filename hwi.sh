#!/bin/bash

# HardWare Inspector (Improved Storage & RAID Tree)
# Minimal dependencies, maximum speed.

set -Eeuo pipefail
shopt -s nullglob

SHOW_LOGO=true
for arg in "$@"; do
    [[ "$arg" == "-nologo" ]] && SHOW_LOGO=false
done

# --- Color System ---
ESC=$'\033'
B="${ESC}[1m";  _B="${ESC}[22m"
I="${ESC}[3m";  _I="${ESC}[23m"
U="${ESC}[4m";  _U="${ESC}[24m"
RED="${ESC}[31m";   _RED="${ESC}[39m"
GRN="${ESC}[32m";   _GRN="${ESC}[39m"
YLW="${ESC}[33m";   _YLW="${ESC}[39m"
BLU="${ESC}[34m";   _BLU="${ESC}[39m"
MAG="${ESC}[35m";   _MAG="${ESC}[39m"
CYN="${ESC}[36m";   _CYN="${ESC}[39m"
GRY="${ESC}[90m";   _GRY="${ESC}[39m"

USE_COLOR=true
IS_INTERACTIVE=true
[[ ! -t 1 ]] && { USE_COLOR=false; IS_INTERACTIVE=false; }

cprintf() {
    local t="${1:-}"
    if ! $USE_COLOR; then
        t="${t//\[bold\]/}";      t="${t//\[\/bold\]/}"
        t="${t//\[italic\]/}";    t="${t//\[\/italic\]/}"
        t="${t//\[underline\]/}"; t="${t//\[\/underline\]/}"
        t="${t//\[red\]/}";       t="${t//\[\/red\]/}"
        t="${t//\[green\]/}";     t="${t//\[\/green\]/}"
        t="${t//\[yellow\]/}";    t="${t//\[\/yellow\]/}"
        t="${t//\[blue\]/}";      t="${t//\[\/blue\]/}"
        t="${t//\[magenta\]/}";   t="${t//\[\/magenta\]/}"
        t="${t//\[cyan\]/}";      t="${t//\[\/cyan\]/}"
        t="${t//\[gray\]/}";      t="${t//\[\/gray\]/}"
        printf '%b' "$t"
        return
    fi
    t="${t//\[bold\]/$B}";      t="${t//\[\/bold\]/$_B}"
    t="${t//\[italic\]/$I}";    t="${t//\[\/italic\]/$_I}"
    t="${t//\[underline\]/$U}"; t="${t//\[\/underline\]/$_U}"
    t="${t//\[red\]/$RED}";     t="${t//\[\/red\]/$_RED}"
    t="${t//\[green\]/$GRN}";   t="${t//\[\/green\]/$_GRN}"
    t="${t//\[yellow\]/$YLW}";  t="${t//\[\/yellow\]/$_YLW}"
    t="${t//\[blue\]/$BLU}";    t="${t//\[\/blue\]/$_BLU}"
    t="${t//\[magenta\]/$MAG}"; t="${t//\[\/magenta\]/$_MAG}"
    t="${t//\[cyan\]/$CYN}";    t="${t//\[\/cyan\]/$_CYN}"
    t="${t//\[gray\]/$GRY}";    t="${t//\[\/gray\]/$_GRY}"
    printf '%b' "$t"
}

cleanup() {
    local exit_code=$?
    if [[ "$IS_INTERACTIVE" == "true" ]]; then
        printf "\r\033[K\033[?25h" >&2
    fi
    exit "$exit_code"
}

trap cleanup EXIT
trap 'exit 1' ERR

log_step() {
    [[ "$IS_INTERACTIVE" == "true" ]] && printf "\r\033[K${GRY}Generating report: $1...${_GRY}" >&2
}

trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}

# --- 1. Data Collection & Initializing ---
log_step "Initializing"
STR_VIRT=""
STR_SYS=""
STR_GPU=""
STR_STORAGE=""
STR_RAID=""
STR_NET=""
STR_EXT=""
RAM_STR="N/A"

log_step "OS & Kernel"
OS_NAME="Linux"
if [[ -f /etc/os-release ]]; then
    OS_NAME=$(grep "^PRETTY_NAME=" /etc/os-release | cut -d= -f2- | tr -d '"' || echo "Linux")
fi
KERNEL=$(uname -r)
ARCH=$(uname -m)
HOSTNAME=$(hostname 2>/dev/null || echo "${HOSTNAME:-Unknown}")
LOCAL_TIME=$(date "+%Y-%m-%d %H:%M:%S %Z")
PROCS=$(ls -d /proc/[0-9]* 2>/dev/null | wc -l || echo "N/A")
ENTROPY=$(cat /proc/sys/kernel/random/entropy_avail 2>/dev/null || echo "N/A")

log_step "Virtualization"
VIRT="none"
if [[ -f /sys/class/dmi/id/sys_vendor ]]; then
    vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "")
    case "${vendor,,}" in
        *qemu*|*kvm*) VIRT="kvm" ;;
        *vmware*) VIRT="vmware" ;;
        *oracle*) VIRT="vbox" ;;
        *microsoft*) VIRT="hyper-v" ;;
    esac
fi
[[ "$VIRT" != "none" ]] && STR_VIRT="[bold][blue][Virt]:[/blue][/bold]    $VIRT"$'\n'

log_step "Uptime & CPU"
read -r up_sec _ < /proc/uptime || up_sec=0
up_d=$(( ${up_sec%.*} / 86400 ))
up_h=$(( (${up_sec%.*} % 86400) / 3600 ))
up_m=$(( (${up_sec%.*} % 3600) / 60 ))
UPTIME="${up_d}d ${up_h}h ${up_m}m"
read -r l1 l2 l3 _ < /proc/loadavg || l1="N/A"; l2="N/A"; l3="N/A"
LOAD="$l1, $l2, $l3"

CPU_MODEL="Unknown"
CPU_CORES=0
if [[ -f /proc/cpuinfo ]]; then
    while read -r line; do
        if [[ $line == "model name"* ]]; then
            CPU_MODEL="${line#*: }"
        elif [[ $line == "processor"* ]]; then
            ((++CPU_CORES))
        fi
    done < /proc/cpuinfo
fi
CPU_MODEL=$(trim "$CPU_MODEL")

TEMP="N/A"
if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
    raw_temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
    [[ "$raw_temp" -gt 0 ]] && TEMP="$((raw_temp / 1000)).$(( (raw_temp % 1000) / 100 ))°C"
fi

log_step "Memory"
tot=0; avl=0; swp_t=0; swp_f=0
if [[ -f /proc/meminfo ]]; then
    while read -r key val _; do
        case "$key" in
            MemTotal:) tot=$((val / 1024)) ;;
            MemAvailable:) avl=$((val / 1024)) ;;
            SwapTotal:) swp_t=$((val / 1024)) ;;
            SwapFree:) swp_f=$((val / 1024)) ;;
        esac
    done < /proc/meminfo
fi
RAM_STR="Total: $((tot / 1024)) GB, Available: $((avl / 1024)) GB"
[[ $swp_t -gt 0 ]] && RAM_STR+=", Swap: $(( (swp_t - swp_f) / 1024 ))/$((swp_t / 1024)) GB"

log_step "Mounts"
declare -A MOUNTS
if [[ -f /proc/mounts ]]; then
    while read -r dev mnt _; do
        [[ "$dev" == /dev/* ]] || continue
        node="${dev##*/}"
        [[ "$dev" == /dev/mapper/* || -L "$dev" ]] && {
            real_dev=$(readlink -f "$dev" 2>/dev/null || echo "$dev")
            node="${real_dev##*/}"
        }
        MOUNTS["$node"]+="${mnt} "
    done < /proc/mounts
fi

# --- 2. Storage Tree ---
log_step "Storage Tree"

format_size() {
    local sectors="$1"
    local size_gb=$(( sectors * 512 / 1073741824 ))
    [[ $size_gb -eq 0 ]] && { echo "$(( sectors * 512 / 1048576 )) MB"; return; }
    echo "$size_gb GB"
}

get_dm_type() {
    local dev="$1"
    local uuid=$(cat "/sys/class/block/$dev/dm/uuid" 2>/dev/null || echo "")
    [[ "$uuid" == LVM-* ]] && echo "lvm" && return
    [[ "$uuid" == CRYPT-* ]] && echo "crypt" && return
    echo "dm"
}

render_block() {
    local dev="$1"
    local indent="$2"
    local is_last="$3"
    local is_root="${4:-false}"
    local call_stack="${5:-}"

    # Infinite loop protection per branch
    [[ "$call_stack" == *" $dev "* ]] && return
    local current_stack="$call_stack $dev "

    local path="/sys/class/block/$dev"
    [[ -d "$path" ]] || return
    
    local sectors=$(cat "$path/size" 2>/dev/null || echo 0)
    [[ $sectors -eq 0 && "$is_root" == "false" ]] && return
    
    local prefix="├─ "
    [[ "$is_last" == "true" ]] && prefix="└─ "
    [[ "$is_root" == "true" ]] && prefix=""

    local display_name="/dev/$dev"
    local details=""
    if [[ -f "$path/dm/name" ]]; then
        display_name="/dev/mapper/$(cat "$path/dm/name")"
        details="($dev, $(get_dm_type "$dev"))"
    elif [[ -f "$path/md/level" ]]; then
        details="($dev, $(cat "$path/md/level" 2>/dev/null || echo "raid"))"
    elif [[ "$is_root" == "true" ]]; then
        local model=$(trim "$(cat "$path/device/model" 2>/dev/null || echo "")")
        [[ -n "$model" ]] && details="($model)"
    fi

    local mnt_raw=$(trim "${MOUNTS[$dev]:-}")
    local mnts=($mnt_raw)
    
    local children=()
    if [[ "$is_root" == "true" ]]; then
        for p_path in "$path"/*; do
            [[ -f "$p_path/partition" ]] && children+=("${p_path##*/}")
        done
        # Also check if disk itself is a holder (rare but possible for raid on disks)
        for h_path in "$path/holders"/*; do
            [[ -d "$h_path" ]] && children+=("${h_path##*/}")
        done
    else
        for h_path in "$path/holders"/*; do
            [[ -d "$h_path" ]] && children+=("${h_path##*/}")
        done
    fi

    STR_STORAGE+="${indent}${prefix}${display_name}: [yellow]$(format_size "$sectors")[/yellow] ${details}"$'\n'

    local next_indent="${indent}│  "
    [[ "$is_last" == "true" || "$is_root" == "true" ]] && next_indent="${indent}   "
    [[ "$is_root" == "true" ]] && next_indent="${indent}"

    local m_count=${#mnts[@]}
    local h_count=${#children[@]}
    local total=$((m_count + h_count))

    for ((i=0; i<m_count; i++)); do
        local m_char="├─ "; [[ $((i + 1)) -eq $total ]] && m_char="└─ "
        STR_STORAGE+="${next_indent}${m_char}[cyan]${mnts[$i]}[/cyan]"$'\n'
    done

    for ((i=0; i<h_count; i++)); do
        local last="false"; [[ $((i + m_count + 1)) -eq $total ]] && last="true"
        render_block "${children[$i]}" "$next_indent" "$last" "false" "$current_stack"
    done
}

for dev_path in /sys/class/block/*; do
    devname="${dev_path##*/}"
    [[ "$devname" =~ ^(loop|ram|sr|nbd|md|dm-|zram) ]] && continue
    [[ -f "$dev_path/partition" ]] && continue
    render_block "$devname" "  " "true" "true"
done

log_step "RAID & Network"
if [[ -f /proc/mdstat ]]; then
    while read -r line; do
        [[ "$line" =~ ^md[0-9] ]] || continue
        dev="${line%% :*}"
        status="${line#* : }"
        
        # Colorize status
        s_color="yellow"
        [[ "$status" == *"active"* || "$status" == *"clean"* ]] && s_color="green"
        [[ "$status" == *"degraded"* || "$status" == *"FAILED"* ]] && s_color="red"
        
        sectors=$(cat "/sys/class/block/$dev/size" 2>/dev/null || echo 0)
        STR_RAID+="- /dev/$dev: [yellow]$(format_size "$sectors")[/yellow] ([$s_color]$status[/$s_color])"$'\n'
        
        # Add RAID members as sub-tree
        local slaves=(/sys/class/block/$dev/slaves/*)
        local s_count=${#slaves[@]}
        for ((i=0; i<s_count; i++)); do
            s_char="├─ "; [[ $((i+1)) -eq $s_count ]] && s_char="└─ "
            s_name="${slaves[$i]##*/}"
            STR_RAID+="  ${s_char}${s_name}"$'\n'
        done
    done < /proc/mdstat
fi

gw=""
if command -v ip >/dev/null; then
    gw=$(timeout 1 ip route | awk '/default/ {print $3}' | head -n1 || echo "")
fi
[[ -n "$gw" ]] && STR_NET+="  - Default Gateway: [cyan]$gw[/cyan]"$'\n'

for net_path in /sys/class/net/*; do
    iface="${net_path##*/}"
    [[ "$iface" =~ ^(lo|veth|docker|br-|virbr|vlan) ]] && continue
    mac=$(cat "$net_path/address" 2>/dev/null || echo "Unknown")
    state=$(cat "$net_path/operstate" 2>/dev/null || echo "Unknown")
    state_color="red"; [[ "$state" == "up" ]] && state_color="green"
    
    ssid=""
    if [[ -d "$net_path/wireless" || -d "$net_path/phy80211" ]]; then
        if command -v iwgetid >/dev/null; then
            ssid=$(timeout 1 iwgetid -r "$iface" 2>/dev/null || echo "")
        elif command -v nmcli >/dev/null; then
            ssid=$(timeout 1 nmcli --timeout 1 -t -f active,ssid dev wifi 2>/dev/null | grep "^yes" | cut -d: -f2 || echo "")
        fi
    fi
    [[ -n "$ssid" ]] && ssid=" SSID: [yellow]$ssid[/yellow],"

    ips=""
    if command -v ip >/dev/null; then
        ips=$(timeout 1 ip -4 addr show dev "$iface" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 || echo "")
    fi
    ips=$(trim "${ips//$'\n'/,}")
    STR_NET+="  - [yellow]$iface[/yellow]:${ssid} MAC $mac, State: [$state_color]$state[/$state_color], IP: [cyan]${ips:-None}[/cyan]"$'\n'
done

log_step "GPU & Hardware"
if command -v lspci >/dev/null; then
    while read -r gpu; do
        STR_GPU+="  - $gpu"$'\n'
    done < <(timeout 2 lspci 2>/dev/null | grep -iE 'vga|3d|display' | cut -d: -f3- | sed 's/^ //' || true)
fi
[[ -n "$STR_GPU" ]] && STR_GPU="[bold][blue][GPU]:[/blue][/bold]"$'\n'"$STR_GPU"

log_step "External IP"
if command -v curl >/dev/null; then
    EXT_IP=$(curl -s --max-time 2 https://ifconfig.me 2> /dev/null || echo "N/A")
    STR_EXT="  - External IP: [cyan]$EXT_IP[/cyan]"$'\n'
fi

log_step "System DMI"
if [[ -f /sys/class/dmi/id/sys_vendor ]]; then
    dmi_v=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "Unknown")
    dmi_p=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "Unknown")
    STR_SYS+="[bold][blue][System]:[/blue][/bold]  ${dmi_v} ${dmi_p}"$'\n'
fi

# Logo
STR_LOGO=""
if $SHOW_LOGO; then
    STR_LOGO="[bold][cyan]
              ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
              ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
              ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
              ░▒▓████████▓▒░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
              ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
              ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
              ░▒▓█▓▒░░▒▓█▓▒░░▒▓█████████████▓▒░░▒▓█▓▒░ 

         ░█▀▀░█░█░█▀▀░▀█▀░█▀▀░█▄█░░░█▀▄░█▀▀░█▀█░█▀█░█▀▄░▀█▀░
         ░▀▀█░░█░░▀▀█░░█░░█▀▀░█░█░░░█▀▄░█▀▀░█▀▀░█░█░█▀▄░░█░░
         ░▀▀▀░░▀░░▀▀▀░░▀░░▀▀▀░▀░▀░░░▀░▀░▀▀▀░▀░░░▀▀▀░▀░▀░░▀░░
                                                             
         ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
[/cyan][/bold]"$'\n'
fi

REPORT="${STR_LOGO}"
REPORT+="[bold][blue][OS]:[/blue][/bold]      $OS_NAME ($ARCH)"$'\n'
REPORT+="[bold][blue][Hostname]:[/blue][/bold] $HOSTNAME"$'\n'
REPORT+="[bold][blue][Kernel]:[/blue][/bold]  $KERNEL"$'\n'
REPORT+="${STR_VIRT}"
REPORT+="[bold][blue][Uptime]:[/blue][/bold]  $UPTIME (Load: $LOAD)"$'\n'
REPORT+="[bold][blue][Context]:[/blue][/bold] $LOCAL_TIME (Procs: $PROCS, Entropy: $ENTROPY)"$'\n'
REPORT+="${STR_SYS}"
REPORT+="[bold][blue][CPU]:[/blue][/bold]     $CPU_MODEL ($CPU_CORES cores) @ [yellow]$TEMP[/yellow]"$'\n'
REPORT+="[bold][blue][RAM]:[/blue][/bold]     $RAM_STR"$'\n'
REPORT+="${STR_GPU}"
REPORT+="[bold][blue][Storage Tree]:[/blue][/bold]"$'\n'"$STR_STORAGE"
[[ -n "$STR_RAID" ]] && REPORT+="[bold][blue][RAID Status]:[/blue][/bold]"$'\n'"$STR_RAID"
REPORT+="[bold][blue][Network]:[/blue][/bold]"$'\n'"$STR_NET"
REPORT+="${STR_EXT}"

if [[ "$IS_INTERACTIVE" == "true" ]]; then
    printf "\r\033[K\033[?25h" >&2
    trap - EXIT
fi
cprintf "$REPORT"
