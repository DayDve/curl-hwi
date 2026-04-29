#!/bin/bash

# HardWare Inspector (Fixed Pure Bash Edition)
# Minimal dependencies, maximum speed.

set -Eeuo pipefail

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

# Auto-detect modes
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

# --- Error Handling ---
cleanup() {
    local exit_code=$?
    if [[ "$IS_INTERACTIVE" == "true" ]]; then
        printf "\r\033[K\033[?25h" >&2
    fi
    exit "$exit_code"
}

error_handler() {
    local line=$1
    cprintf "\n[bold][red]Error:[/red][/bold] Script failed at line [yellow]$line[/yellow]\n" >&2
}

trap cleanup EXIT
trap 'error_handler $LINENO' ERR

# Quick status
if $IS_INTERACTIVE; then
    printf "\033[?25l${GRY}Generating report...${_GRY}" >&2
fi

trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}

# --- 1. Data Collection ---
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

read -r up_sec _ < /proc/uptime
up_d=$(( ${up_sec%.*} / 86400 ))
up_h=$(( (${up_sec%.*} % 86400) / 3600 ))
up_m=$(( (${up_sec%.*} % 3600) / 60 ))
UPTIME="${up_d}d ${up_h}h ${up_m}m"
read -r l1 l2 l3 _ < /proc/loadavg
LOAD="$l1, $l2, $l3"

CPU_MODEL="Unknown"
CPU_CORES=0
while read -r line; do
    if [[ $line == "model name"* ]]; then
        CPU_MODEL="${line#*: }"
    elif [[ $line == "processor"* ]]; then
        ((++CPU_CORES))
    fi
done < /proc/cpuinfo
CPU_MODEL=$(trim "$CPU_MODEL")

TEMP="N/A"
if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
    raw_temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
    [[ "$raw_temp" -gt 0 ]] && TEMP="$((raw_temp / 1000)).$(( (raw_temp % 1000) / 100 ))°C"
fi

while read -r key val _; do
    case "$key" in
        MemTotal:) tot=$((val / 1024)) ;;
        MemAvailable:) avl=$((val / 1024)) ;;
        SwapTotal:) swp_t=$((val / 1024)) ;;
        SwapFree:) swp_f=$((val / 1024)) ;;
    esac
done < /proc/meminfo

# --- 2. Preparing Lists and Sections ---

# Basic Info Extensions
STR_VIRT=""
[[ "$VIRT" != "none" ]] && STR_VIRT="[bold][blue][Virt]:[/blue][/bold]    $VIRT"$'\n'

# System info
STR_SYS=""
if [[ -r /sys/class/dmi/id/sys_vendor ]]; then
    v=$(trim "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "Unknown")")
    p=$(trim "$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "Unknown")")
    STR_SYS+="[bold][blue][System]:[/blue][/bold]  ${v} ${p}"$'\n'
    
    bv=$(trim "$(cat /sys/class/dmi/id/board_vendor 2>/dev/null || echo "Unknown")")
    bn=$(trim "$(cat /sys/class/dmi/id/board_name 2>/dev/null || echo "")")
    [[ -n "$bn" && "$bn" != "$p" ]] && STR_SYS+="[bold][blue][MB]:[/blue][/bold]      ${bv} ${bn}"$'\n'

    bios_v=$(trim "$(cat /sys/class/dmi/id/bios_version 2>/dev/null || echo "")")
    bios_d=$(trim "$(cat /sys/class/dmi/id/bios_date 2>/dev/null || echo "")")
    [[ -n "$bios_v" ]] && STR_SYS+="[bold][blue][BIOS]:[/blue][/bold]    ${bios_v} (${bios_d})"$'\n'
fi

# Battery
STR_BATTERY=""
for bat in /sys/class/power_supply/BAT*; do
    if [[ -d "$bat" ]]; then
        cap=$(cat "$bat/capacity" 2>/dev/null || echo "")
        stat=$(cat "$bat/status" 2>/dev/null || echo "Unknown")
        [[ -n "$cap" ]] && STR_BATTERY+="[bold][blue][Battery]:[/blue][/bold] ${cap}% (${stat})"$'\n'
    fi
done

# RAM & ZRAM
RAM_STR="Total: $((tot / 1024)) GB, Available: $((avl / 1024)) GB"
if command -v dmidecode >/dev/null; then
    dmi=$(dmidecode -t 17 2>/dev/null || echo "")
    if [[ -n "$dmi" ]]; then
        slots=$(grep -c "Memory Device" <<< "$dmi" || true)
        sticks=$(grep -c "Size: [0-9]" <<< "$dmi" || true)
        type=$(grep -m1 "Type:" <<< "$dmi" | cut -d: -f2 | tr -d ' ' || echo "")
        speed=$(grep -m1 "Speed:" <<< "$dmi" | cut -d: -f2 | tr -d ' ' || echo "")
        [[ -n "$type" && "$type" != "Unknown" ]] && RAM_STR+=" ($type"
        [[ -n "$speed" && "$speed" != "Unknown" ]] && RAM_STR+=", $speed"
        [[ $slots -gt 0 ]] && RAM_STR+=", Slots: $sticks/$slots"
        [[ "$RAM_STR" == *"("* ]] && RAM_STR+=")"
    fi
fi
if [[ -f /sys/block/zram0/disksize ]]; then
    zsize=$(cat /sys/block/zram0/disksize 2>/dev/null || echo 0)
    [[ $zsize -gt 0 ]] && RAM_STR+=", Zram: $((zsize / 1024 / 1024 / 1024)) GB"
fi
[[ $swp_t -gt 0 ]] && RAM_STR+=", Swap: $(( (swp_t - swp_f) / 1024 ))/$((swp_t / 1024)) GB"

# Physical Storage
STR_STORAGE=""
for dev_path in /sys/class/block/*; do
    devname="${dev_path##*/}"
    [[ "$devname" =~ ^(loop|ram|sr|nbd|md|dm-|zram) ]] && continue
    [[ -f "$dev_path/partition" ]] && continue
    sectors=$(cat "$dev_path/size" 2>/dev/null || continue)
    size_gb=$(( sectors * 512 / 1073741824 ))
    [[ $size_gb -eq 0 ]] && continue
    model=$(trim "$(cat "$dev_path/device/model" 2>/dev/null || echo "")")
    [[ -z "$model" ]] && model="N/A"
    STR_STORAGE+="  - /dev/$devname: [yellow]$size_gb GB[/yellow] ($model)"$'\n'
done

# Logical Volumes, RAID & Btrfs
STR_LOGICAL=""
# MD RAID
if [[ -f /proc/mdstat ]]; then
    while read -r line; do
        [[ "$line" =~ ^md[0-9] ]] || continue
        dev="${line%% :*}"
        status="${line#* : }"
        if [[ -f "/sys/class/block/$dev/size" ]]; then
            s=$(cat "/sys/class/block/$dev/size")
            STR_LOGICAL+="  - /dev/$dev: [yellow]$(( s * 512 / 1073741824 )) GB[/yellow] ($status)"$'\n'
        else
            STR_LOGICAL+="  - /dev/$dev: $status"$'\n'
        fi
    done < /proc/mdstat
fi
# LVM / Device Mapper
for dm_path in /sys/class/block/dm-*; do
    [[ -d "$dm_path/dm" ]] || continue
    dm_name=$(cat "$dm_path/dm/name" 2>/dev/null || continue)
    sectors=$(cat "$dm_path/size" 2>/dev/null || continue)
    size_gb=$(( sectors * 512 / 1073741824 ))
    [[ $size_gb -eq 0 ]] && continue
    STR_LOGICAL+="  - /dev/mapper/$dm_name: [yellow]$size_gb GB[/yellow] (LVM/DM)"$'\n'
done
# Btrfs Pools
if [[ -d /sys/fs/btrfs ]]; then
    for fs_path in /sys/fs/btrfs/*; do
        [[ -f "$fs_path/label" ]] || continue
        uuid="${fs_path##*/}"
        label=$(cat "$fs_path/label" 2>/dev/null || echo "N/A")
        
        # Profile detection
        profile="single"
        for p in raid0 raid1 raid10 raid5 raid6 dup; do
            if [[ -d "$fs_path/allocation/data/$p" ]]; then
                profile="$p"
                break
            fi
        done
        
        # Devices list
        devs=""
        for d in "$fs_path/devices"/*; do
            devs+="${d##*/}, "
        done
        STR_LOGICAL+="  - Btrfs Pool: Label: [cyan]${label}[/cyan], Profile: [yellow]${profile}[/yellow], Devices: [${devs%, }]"$'\n'
    done
fi

# Partitions
STR_FS=""
while read -r fs type size used avail pcent mount; do
    [[ "$fs" != /dev/* ]] && continue
    STR_FS+="  - [cyan]$mount[/cyan]: [yellow]$size[/yellow] ($type, $pcent used) on [cyan]$fs[/cyan]"$'\n'
done < <(df -hT 2>/dev/null || true)

# Network
STR_NET=""
gw=""
if command -v ip >/dev/null; then
    gw=$(ip route | awk '/default/ {print $3}' | head -n1 || echo "")
elif [[ -f /proc/net/route ]]; then
    while read -r _iface dest gwh _; do
        if [[ "$dest" == "00000000" ]]; then
            a=$(( 0x${gwh:6:2} )); b=$(( 0x${gwh:4:2} )); c=$(( 0x${gwh:2:2} )); d=$(( 0x${gwh:0:2} ))
            gw="$a.$b.$c.$d"
            break
        fi
    done < /proc/net/route
fi
[[ -n "$gw" ]] && STR_NET+="  - Default Gateway: [cyan]$gw[/cyan]"$'\n'

for net_path in /sys/class/net/*; do
    iface="${net_path##*/}"
    [[ "$iface" =~ ^(lo|veth|docker|br-|virbr|vlan) ]] && continue
    mac=$(cat "$net_path/address" 2>/dev/null || echo "Unknown")
    state=$(cat "$net_path/operstate" 2>/dev/null || echo "Unknown")
    state_color="red"
    [[ "$state" == "up" ]] && state_color="green"
    
    ssid=""
    if [[ -d "$net_path/wireless" || -d "$net_path/phy80211" ]]; then
        if command -v iwgetid >/dev/null; then
            ssid=$(iwgetid -r "$iface" 2>/dev/null || echo "")
        elif command -v nmcli >/dev/null; then
            ssid=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | grep "^yes" | cut -d: -f2 || echo "")
        fi
    fi
    [[ -n "$ssid" ]] && ssid=" SSID: [yellow]$ssid[/yellow],"

    ips=""
    if command -v ip >/dev/null; then
        ips=$(ip -4 addr show dev "$iface" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 || echo "")
    elif command -v ifconfig >/dev/null; then
        ips=$(ifconfig "$iface" 2>/dev/null | awk '/inet / {print $2}' | cut -d: -f2 || echo "")
    elif command -v hostname >/dev/null; then
        ips=$(hostname -I 2>/dev/null || echo "")
    fi
    ips=$(trim "${ips//$'\n'/,}")
    STR_NET+="  - [yellow]$iface[/yellow]:${ssid} MAC $mac, State: [$state_color]$state[/$state_color], IP: [cyan]${ips:-None}[/cyan]"$'\n'
done

# GPU
STR_GPU=""
if command -v lspci >/dev/null; then
    while read -r gpu; do
        STR_GPU+="  - $gpu"$'\n'
    done < <(lspci | grep -iE 'vga|3d|display' | cut -d: -f3- | sed 's/^ //' || true)
else
    for dev in /sys/bus/pci/devices/*; do
        [[ ! -f "$dev/class" ]] && continue
        class=$(cat "$dev/class" 2>/dev/null || echo "")
        if [[ "$class" == 0x03* ]]; then
            vendor=$(cat "$dev/vendor" 2>/dev/null || echo "")
            device=$(cat "$dev/device" 2>/dev/null || echo "")
            vname="Unknown Vendor"
            case "$vendor" in
                0x8086) vname="Intel Corporation" ;;
                0x10de) vname="NVIDIA Corporation" ;;
                0x1002|0x1022) vname="Advanced Micro Devices, Inc. [AMD/ATI]" ;;
            esac
            STR_GPU+="  - $vname (ID: ${vendor#0x}:${device#0x})"$'\n'
        fi
    done
fi
[[ -n "$STR_GPU" ]] && STR_GPU="[bold][blue][GPU]:[/blue][/bold]"$'\n'"$STR_GPU"

# External IP
STR_EXT=""
if command -v curl >/dev/null; then
    EXT_IP=$(curl -s --max-time 2 https://ifconfig.me 2> /dev/null || echo "N/A")
    STR_EXT="  - External IP: [cyan]$EXT_IP[/cyan]"$'\n'
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

# Final report assembly
REPORT="${STR_LOGO}"
REPORT+="[bold][blue][OS]:[/blue][/bold]      $OS_NAME ($ARCH)"$'\n'
REPORT+="[bold][blue][Hostname]:[/blue][/bold] $HOSTNAME"$'\n'
REPORT+="[bold][blue][Kernel]:[/blue][/bold]  $KERNEL"$'\n'
REPORT+="${STR_VIRT}"
REPORT+="[bold][blue][Uptime]:[/blue][/bold]  $UPTIME (Load: $LOAD)"$'\n'
REPORT+="[bold][blue][Context]:[/blue][/bold] $LOCAL_TIME (Procs: $PROCS, Entropy: $ENTROPY)"$'\n'
REPORT+="${STR_SYS}"
REPORT+="${STR_BATTERY}"
REPORT+="[bold][blue][CPU]:[/blue][/bold]     $CPU_MODEL ($CPU_CORES cores) @ [yellow]$TEMP[/yellow]"$'\n'
REPORT+="[bold][blue][RAM]:[/blue][/bold]     $RAM_STR"$'\n'
REPORT+="${STR_GPU}"
REPORT+="[bold][blue][Physical Storage]:[/blue][/bold]"$'\n'"$STR_STORAGE"
[[ -n "$STR_LOGICAL" ]] && REPORT+="[bold][blue][Logical Volumes & RAID]:[/blue][/bold]"$'\n'"$STR_LOGICAL"
REPORT+="[bold][blue][Partitions & FS]:[/blue][/bold]"$'\n'"$STR_FS"
REPORT+="[bold][blue][Network]:[/blue][/bold]"$'\n'"$STR_NET"
REPORT+="${STR_EXT}"

# Final flush
if [[ "$IS_INTERACTIVE" == "true" ]]; then
    printf "\r\033[K\033[?25h" >&2
    trap - EXIT
fi
cprintf "$REPORT"
