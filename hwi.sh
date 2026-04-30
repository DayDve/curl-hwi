#!/bin/bash

# HardWare Inspector (High Performance Storage Tree)
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
    [[ -n "$t" ]] || return
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
        printf '%s\n' "$t"
        return
    fi
    # Process line-by-line to avoid quadratic complexity on large strings
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line//\[bold\]/$B}";      line="${line//\[\/bold\]/$_B}"
        line="${line//\[italic\]/$I}";    line="${line//\[\/italic\]/$_I}"
        line="${line//\[underline\]/$U}"; line="${line//\[\/underline\]/$_U}"
        line="${line//\[red\]/$RED}";     line="${line//\[\/red\]/$_RED}"
        line="${line//\[green\]/$GRN}";   line="${line//\[\/green\]/$_GRN}"
        line="${line//\[yellow\]/$YLW}";  line="${line//\[\/yellow\]/$_YLW}"
        line="${line//\[blue\]/$BLU}";    line="${line//\[\/blue\]/$_BLU}"
        line="${line//\[magenta\]/$MAG}"; line="${line//\[\/magenta\]/$_MAG}"
        line="${line//\[cyan\]/$CYN}";    line="${line//\[\/cyan\]/$_CYN}"
        line="${line//\[gray\]/$GRY}";    line="${line//\[\/gray\]/$_GRY}"
        printf '%b\n' "$line"
    done <<< "$t"
}

cleanup() {
    local exit_code=$?
    if [[ "$IS_INTERACTIVE" == "true" ]]; then
        printf "\r\033[K\033[?25h" >&2
    fi
    exit "$exit_code"
}

trap cleanup EXIT

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
[[ -f /etc/os-release ]] && OS_NAME=$(grep "^PRETTY_NAME=" /etc/os-release | cut -d= -f2- | tr -d '"' || echo "Linux")
KERNEL=$(uname -r); ARCH=$(uname -m)
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
[[ "$VIRT" != "none" ]] && STR_VIRT="[bold][blue][Virt]:[/blue][/bold]      $VIRT"$'\n'

log_step "System DMI"
SYS_MODEL="Unknown"; MB_MODEL="Unknown"
if [[ -f /sys/class/dmi/id/product_name ]]; then
    vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "")
    product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "")
    SYS_MODEL=$(trim "$vendor $product")
fi
if [[ -f /sys/class/dmi/id/board_name ]]; then
    b_vendor=$(cat /sys/class/dmi/id/board_vendor 2>/dev/null || echo "")
    b_name=$(cat /sys/class/dmi/id/board_name 2>/dev/null || echo "")
    MB_MODEL=$(trim "$b_vendor $b_name")
fi

log_step "Uptime & CPU"
read -r up_sec _ < /proc/uptime || up_sec=0
up_d=$(( ${up_sec%.*} / 86400 )); up_h=$(( (${up_sec%.*} % 86400) / 3600 )); up_m=$(( (${up_sec%.*} % 3600) / 60 ))
UPTIME="${up_d}d ${up_h}h ${up_m}m"
read -r l1 l2 l3 _ < /proc/loadavg || l1="N/A"; l2="N/A"; l3="N/A"
LOAD="$l1, $l2, $l3"

CPU_MODEL="Unknown"; CPU_CORES=0
if [[ -f /proc/cpuinfo ]]; then
    while read -r line; do
        [[ $line == "model name"* ]] && CPU_MODEL="${line#*: }"
        [[ $line == "processor"* ]] && ((++CPU_CORES))
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
        # Skip readlink for common paths to speed up
        [[ "$dev" == /dev/mapper/* || -L "$dev" ]] && {
            real_dev=$(readlink -f "$dev" 2>/dev/null || echo "$dev")
            node="${real_dev##*/}"
        }
        MOUNTS["$node"]+="${mnt} "
    done < /proc/mounts
fi

# --- 2. Storage Tree Core ---
log_step "Storage Tree"
declare -A PROCESSED_DEVS

format_size() {
    local sectors="$1"; local size_gb=$(( sectors * 512 / 1073741824 ))
    [[ $size_gb -eq 0 ]] && { echo "$(( sectors * 512 / 1048576 )) MB"; return; }
    echo "$size_gb GB"
}

get_dm_type() {
    local dev="$1"; local uuid=$(cat "/sys/class/block/$dev/dm/uuid" 2>/dev/null || echo "")
    [[ "$uuid" == LVM-* ]] && echo "lvm" && return; [[ "$uuid" == CRYPT-* ]] && echo "crypt" && return; echo "dm"
}

# --- Unified Tree Rendering Engine ---
# render_tree_node name details stack c_idx t_sibs total_children is_root
# Sets global TREE_LINE and TREE_STACK
render_tree_node() {
    local name="$1" details="$2" stack="$3" c_idx="$4" t_sibs="$5" total="$6" is_root="$7"
    local prefix=""; local n_stack=""
    local W=$((total + 1))
    
    if [[ "$is_root" == "true" ]]; then
        prefix=" ┌"; for ((i=0; i<total-1; i++)); do prefix+="┬"; done
        while [[ ${#prefix} -lt $((W+1)) ]]; do prefix+="─"; done
        n_stack=" "
    else
        prefix="$stack"
        for ((i=0; i<t_sibs-c_idx-1; i++)); do prefix+="│"; done
        n_stack="$prefix"
        prefix+="└"
        for ((i=0; i<c_idx; i++)); do prefix+="─"; done
        if [[ $total -gt 0 ]]; then prefix+="┬"; else prefix+="─"; fi
        # Child stack: vertical lines + (c_idx + 1) spaces to align with ┬
        for ((i=0; i<c_idx + 1; i++)); do n_stack+=" "; done
    fi
    
    TREE_LINE="${prefix}${name}"
    [[ -n "$details" ]] && TREE_LINE+=": $details"
    TREE_STACK="$n_stack"
}

# render_storage_tree dev stack c_idx t_sibs is_root
render_storage_tree() {
    local dev="$1" stack="$2" c_idx="$3" t_sibs="$4" is_root="$5"
    [[ -n "${PROCESSED_DEVS[$dev]:-}" ]] && return; PROCESSED_DEVS["$dev"]=1
    
    local path="/sys/class/block/$dev"; [[ -d "$path" ]] || return
    local sectors=$(cat "$path/size" 2>/dev/null || echo 0)
    [[ $sectors -eq 0 && "$is_root" == "false" ]] && return
    
    local mnts=( ${MOUNTS[$dev]:-} ); local children=()
    if [[ "$is_root" == "true" ]]; then
        for p_path in "$path"/${dev}*; do [[ -f "$p_path/partition" ]] && children+=("${p_path##*/}"); done
    fi
    for h_path in "$path/holders"/*; do
        [[ -d "$h_path" ]] || continue
        local hn="${h_path##*/}"
        local skip=false; for c in "${children[@]}"; do [[ "$c" == "$hn" ]] && skip=true && break; done
        [[ "$skip" == "true" ]] && continue
        children+=("$hn")
    done
    
    local total=$(( ${#mnts[@]} + ${#children[@]} ))
    local display_name="/dev/$dev"; local details="[yellow]$(format_size "$sectors")[/yellow]"
    if [[ -f "$path/dm/name" ]]; then
        display_name="/dev/mapper/$(cat "$path/dm/name")"; details+=" ($dev, $(get_dm_type "$dev"))"
    elif [[ -f "$path/md/level" ]]; then details+=" ($dev, $(cat "$path/md/level" 2>/dev/null || echo "raid"))"
    elif [[ -f "$path/device/model" ]]; then
        local model=$(trim "$(cat "$path/device/model" 2>/dev/null || echo "")")
        [[ -n "$model" ]] && [[ ! "$dev" =~ [0-9]$ ]] && details+=" ($model)"
    fi

    render_tree_node "$display_name" "$details" "$stack" "$c_idx" "$t_sibs" "$total" "$is_root"
    STR_STORAGE+="$TREE_LINE"$'\n'
    local n_stack="$TREE_STACK"

    for ((i=0; i<${#mnts[@]}; i++)); do
        render_tree_node "[cyan]${mnts[$i]}[/cyan]" "" "$n_stack" "$i" "$total" 0 "false"
        STR_STORAGE+="$TREE_LINE"$'\n'
    done
    for ((i=0; i<${#children[@]}; i++)); do
        render_storage_tree "${children[$i]}" "$n_stack" "$((i+${#mnts[@]}))" "$total" "false"
    done
}

ROOT_NODES=()
for d_path in /sys/class/block/*; do
    dn="${d_path##*/}"; [[ "$dn" =~ ^(loop|ram|sr|nbd|md|dm-|zram) ]] && continue
    [[ -f "$d_path/partition" ]] && continue
    ROOT_NODES+=("$dn")
done
for ((i=0; i<${#ROOT_NODES[@]}; i++)); do render_storage_tree "${ROOT_NODES[$i]}" "" 0 0 "true"; done

log_step "RAID Status"
STR_RAID=""
if [[ -f /proc/mdstat ]]; then
    while read -r line; do
        [[ "$line" =~ ^md[0-9]+ ]] || continue
        md_dev="${line%% :*}"; rest="${line#* : }"; status_word="${rest%% *}"
        l_s="${rest#$status_word }"; raid_level="${l_s%% *}"; slaves_part="${l_s#$raid_level }"
        s_color="yellow"; [[ "$status_word" == *"active"* ]] && s_color="green"
        sectors=$(cat "/sys/class/block/$md_dev/size" 2>/dev/null || echo 0)
        read -ra slaves_arr <<< "$slaves_part"
        
        render_tree_node "/dev/$md_dev" "[yellow]$(format_size "$sectors")[/yellow] ([$s_color]$status_word $raid_level[/$s_color])" "" 0 0 "${#slaves_arr[@]}" "true"
        STR_RAID+="$TREE_LINE"$'\n'
        local n_stack="$TREE_STACK"
        for ((i=0; i<${#slaves_arr[@]}; i++)); do
            render_tree_node "${slaves_arr[$i]}" "" "$n_stack" "$i" "${#slaves_arr[@]}" 0 "false"
            STR_RAID+="$TREE_LINE"$'\n'
        done
    done < /proc/mdstat
fi

gw=""
if command -v ip >/dev/null; then gw=$(timeout 1 ip route | awk '/default/ {print $3}' | head -n1 || echo ""); fi
[[ -n "$gw" ]] && STR_NET+="  - Default Gateway: [cyan]$gw[/cyan]"$'\n'

for net_path in /sys/class/net/*; do
    iface="${net_path##*/}"
    [[ "$iface" =~ ^(lo|veth|docker|br-|virbr|vlan) ]] && continue
    mac=$(cat "$net_path/address" 2>/dev/null || echo "Unknown")
    state=$(cat "$net_path/operstate" 2>/dev/null || echo "Unknown")
    state_color="red"; [[ "$state" == "up" ]] && state_color="green"
    ssid=""
    if [[ -d "$net_path/wireless" || -d "$net_path/phy80211" ]]; then
        if command -v iwgetid >/dev/null; then ssid=$(timeout 1 iwgetid -r "$iface" 2>/dev/null || echo "")
        elif command -v nmcli >/dev/null; then ssid=$(timeout 1 nmcli --timeout 1 -t -f active,ssid dev wifi 2>/dev/null | grep "^yes" | cut -d: -f2 || echo ""); fi
    fi
    [[ -n "$ssid" ]] && ssid=" SSID: [yellow]$ssid[/yellow],"
    ips=""
    if command -v ip >/dev/null; then ips=$(timeout 1 ip -4 addr show dev "$iface" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 || echo ""); fi
    ips=$(trim "${ips//$'\n'/,}")
    STR_NET+="  - [yellow]$iface[/yellow]:${ssid} MAC $mac, State: [$state_color]$state[/$state_color], IP: [cyan]${ips:-None}[/cyan]"$'\n'
done

log_step "GPU & Hardware"
if command -v lspci >/dev/null; then
    while read -r gpu; do STR_GPU+="  - $gpu"$'\n'; done < <(timeout 2 lspci 2>/dev/null | grep -iE 'vga|3d|display' | cut -d: -f3- | sed 's/^ //' || true)
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
    STR_SYS+="[bold][blue][System]:[/blue][/bold]    ${dmi_v} ${dmi_p}"$'\n'
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

     ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀[/cyan][/bold]"$'\n'
fi
# Assembly
REPORT="${STR_LOGO}"
REPORT+="[bold][blue][OS]:[/blue][/bold]        $OS_NAME ($ARCH)"$'\n'
REPORT+="[bold][blue][Hostname]:[/blue][/bold]  $HOSTNAME"$'\n'
REPORT+="[bold][blue][Kernel]:[/blue][/bold]    $KERNEL"$'\n'
REPORT+="${STR_VIRT}"
REPORT+="[bold][blue][Uptime]:[/blue][/bold]    $UPTIME (Load: $LOAD)"$'\n'
REPORT+="[bold][blue][Context]:[/blue][/bold]   $LOCAL_TIME (Procs: $PROCS, Entropy: $ENTROPY)"$'\n'
REPORT+="[bold][blue][System]:[/blue][/bold]    $SYS_MODEL"$'\n'
REPORT+="[bold][blue][MB]:[/blue][/bold]        $MB_MODEL"$'\n'
REPORT+="[bold][blue][CPU]:[/blue][/bold]       $CPU_MODEL ($CPU_CORES cores) @ [yellow]$TEMP[/yellow]"$'\n'
REPORT+="[bold][blue][RAM]:[/blue][/bold]       $RAM_STR"$'\n'
REPORT+="$STR_GPU"
REPORT+=$'\n'"[bold][blue][Storage Tree]:[/blue][/bold]"$'\n'"$STR_STORAGE"
[[ -n "${STR_RAID//[[:space:]]/}" ]] && REPORT+=$'\n'"[bold][blue][RAID Status]:[/blue][/bold]"$'\n'"$STR_RAID"
REPORT+=$'\n'"[bold][blue][Network]:[/blue][/bold]"$'\n'"$STR_NET"
REPORT+=$'\n'"[bold][blue][External IP]:[/blue][/bold]  $EXT_IP"

if [[ "$IS_INTERACTIVE" == "true" ]]; then
    printf "\r\033[K\033[?25h" >&2
    trap - EXIT
fi
cprintf "$REPORT"
