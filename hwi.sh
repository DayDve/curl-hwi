#!/bin/bash

USE_COLOR=true

cprintf() {
  local text="${1:-}"

  if ! ${USE_COLOR}; then
    text=$(sed -E 's|\[/?[a-zA-Z_]+]||g' <<< "$text")
    printf '%s\n' "$text"
    return
  fi

  local ESC=$'\033'

  text=$(sed -E \
    -e "s|\[bold\]|${ESC}[1m|g" \
    -e "s|\[/bold\]|${ESC}[22m|g" \
    -e "s|\[italic\]|${ESC}[3m|g" \
    -e "s|\[/italic\]|${ESC}[23m|g" \
    -e "s|\[underline\]|${ESC}[4m|g" \
    -e "s|\[/underline\]|${ESC}[24m|g" \
    -e "s|\[blink\]|${ESC}[5m|g" \
    -e "s|\[/blink\]|${ESC}[25m|g" \
    \
    -e "s|\[red\]|${ESC}[31m|g" \
    -e "s|\[/red\]|${ESC}[39m|g" \
    -e "s|\[green\]|${ESC}[32m|g" \
    -e "s|\[/green\]|${ESC}[39m|g" \
    -e "s|\[yellow\]|${ESC}[33m|g" \
    -e "s|\[/yellow\]|${ESC}[39m|g" \
    -e "s|\[blue\]|${ESC}[34m|g" \
    -e "s|\[/blue\]|${ESC}[39m|g" \
    -e "s|\[magenta\]|${ESC}[35m|g" \
    -e "s|\[/magenta\]|${ESC}[39m|g" \
    -e "s|\[cyan\]|${ESC}[36m|g" \
    -e "s|\[/cyan\]|${ESC}[39m|g" \
    -e "s|\[white\]|${ESC}[37m|g" \
    -e "s|\[/white\]|${ESC}[39m|g" \
    -e "s|\[gray\]|${ESC}[90m|g" \
    -e "s|\[/gray\]|${ESC}[39m|g" \
    <<< "$text")

  printf '%b\n' "$text"
}

cprintf_err() {
  cprintf "[bold][red]ERROR[/red][/bold]: $1" >&2
}

cprintf "\n[bold][cyan]=== SYSTEM REPORT ===[/cyan][/bold]\n"

OS_NAME=$(grep -m1 '^PRETTY_NAME=' /etc/os-release 2> /dev/null | cut -d= -f2 | tr -d '"' || echo "Unknown OS")
KERNEL=$(uname -r)
UPTIME=$(uptime -p 2> /dev/null || cat /proc/uptime | awk '{print $1/3600 " hours"}')

cprintf "[bold][blue][OS]:[/blue][/bold]      $OS_NAME (Kernel: $KERNEL)"
cprintf "[bold][blue][Uptime]:[/blue][/bold]  $UPTIME"

if [ -r /sys/class/dmi/id/sys_vendor ]; then
  VEND=$(cat /sys/class/dmi/id/sys_vendor 2> /dev/null | xargs)
  PROD=$(cat /sys/class/dmi/id/product_name 2> /dev/null | xargs)
  BOARD=$(cat /sys/class/dmi/id/board_name 2> /dev/null | xargs)
  cprintf "[bold][blue][System]:[/blue][/bold]  $VEND $PROD"
  cprintf "[bold][blue][Board]:[/blue][/bold]   $BOARD"
else
  cprintf "[bold][blue][System]:[/blue][/bold]  N/A"
fi

CPU_MODEL=$(awk -F': ' '/^model name/ {print $2; exit}' /proc/cpuinfo | xargs)
CPU_CORES=$(grep -c '^processor' /proc/cpuinfo)
cprintf "[bold][blue][CPU]:[/blue][/bold]     $CPU_MODEL ($CPU_CORES cores)"

RAM_STR=$(awk '/^MemTotal:/ {tot=$2} /^MemAvailable:/ {avl=$2} END {printf "Total: %.2f GB, Available: %.2f GB", tot/1024/1024, avl/1024/1024}' /proc/meminfo)
cprintf "[bold][blue][RAM]:[/blue][/bold]     $RAM_STR"

cprintf "[bold][blue][Storage]:[/blue][/bold]"
for dev in /sys/class/block/*; do
  devname=${dev##*/}
  case "$devname" in
  loop* | ram* | sr*) continue ;;
  esac
  [ -f "$dev/partition" ] && continue
  sectors=$(cat "$dev/size" 2> /dev/null || echo 0)
  model="N/A"
  [ -f "$dev/device/model" ] && model=$(cat "$dev/device/model" | xargs)
  size_gb=$(awk "BEGIN {printf \"%.2f\", $sectors * 512 / 1073741824}")
  cprintf "  - /dev/$devname: [yellow]$size_gb GB[/yellow] ($model)"
done

cprintf "[bold][blue][Partitions & FS]:[/blue][/bold]"
df -hT | awk '!/tmpfs|devtmpfs|squashfs|overlay|loop/ && NR>1' | while read -r fs type size used avail pcent mount; do
  cprintf "  - $mount: [yellow]$size[/yellow] ($type, $pcent used) on $fs"
done

cprintf "[bold][blue][Network]:[/blue][/bold]"
for net in /sys/class/net/*; do
  iface=${net##*/}
  case "$iface" in
  lo | veth* | docker* | br-*) continue ;;
  esac
  mac=$(cat "$net/address" 2> /dev/null)
  state=$(cat "$net/operstate" 2> /dev/null)
  speed=$(cat "$net/speed" 2> /dev/null || echo "unknown")

  state_color="red"
  [ "$state" = "up" ] && state_color="green"

  if [ "$speed" != "unknown" ] && [ "$speed" -gt 0 ] 2> /dev/null; then
    speed="${speed} Mbps"
  else
    speed="N/A"
  fi

  iface_ips=""
  if command -v ip > /dev/null 2>&1; then
    iface_ips=$(ip -4 addr show dev "$iface" 2> /dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | xargs | tr ' ' ',')
  elif command -v ifconfig > /dev/null 2>&1; then
    iface_ips=$(ifconfig "$iface" 2> /dev/null | awk '/inet / {print $2}' | xargs | tr ' ' ',')
  fi
  [ -z "$iface_ips" ] && iface_ips="None"

  cprintf "  - $iface: MAC $mac, State: [$state_color]$state[/$state_color], Speed: $speed, IP: [cyan]$iface_ips[/cyan]"
done

EXT_IP=$(curl -s --max-time 3 https://ifconfig.me 2> /dev/null || echo "N/A")
cprintf "  - External IP: [cyan]$EXT_IP[/cyan]"
cprintf ""
