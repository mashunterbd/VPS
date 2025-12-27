#!/usr/bin/env bash
# ============================================================
# VPS INFRASTRUCTURE PRE-FLIGHT CHECK (LINUX)
# Purpose : Decide if a VPS is SAFE for long-term usage
# Includes: Hardware, Storage, Network, SMTP, Automation
# ============================================================

set +e
TIMEOUT=8

PASS=0
FAIL=0
MANUAL=0

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
BLUE="\e[34m"
RESET="\e[0m"

pass()   { echo -e "${GREEN}[PASS]${RESET}  $1"; ((PASS++)); }
fail()   { echo -e "${RED}[FAIL]${RESET}  $1"; ((FAIL++)); }
manual() { echo -e "${YELLOW}[WARN]${RESET}  $1"; ((MANUAL++)); }
info()   { echo -e "\n${BLUE}==>${RESET} $1"; }

timeout_cmd() {
  timeout "$TIMEOUT" bash -c "$1"
}

echo -e "${BLUE}============================================================"
echo " VPS PRE-PURCHASE & POST-PURCHASE CHECK (LINUX)"
echo "============================================================${RESET}"

# ------------------------------------------------------------
info "Operating System"
OS=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
[[ -n "$OS" ]] && echo "OS: $OS" && pass "Operating system detected" || manual "OS information unavailable"

# ------------------------------------------------------------
info "CPU & Virtualization"
CPU_MODEL=$(lscpu | awk -F: '/Model name/ {print $2}' | xargs)
CORES=$(lscpu | awk -F: '/Core\(s\) per socket/ {print $2}' | xargs)
THREADS=$(lscpu | awk -F: '/CPU\(s\)/ {print $2}' | xargs)

echo "CPU Model : $CPU_MODEL"
echo "Cores     : $CORES"
echo "Threads   : $THREADS"
pass "CPU detected"

if lscpu | grep -qi virtualization; then
  pass "CPU virtualization supported"
else
  manual "CPU virtualization not exposed"
fi

# ------------------------------------------------------------
info "Memory (RAM)"
TOTAL_RAM=$(free -g | awk '/Mem:/ {print $2}')
USED_RAM=$(free -g | awk '/Mem:/ {print $3}')
FREE_RAM=$(free -g | awk '/Mem:/ {print $4}')

echo "Total RAM : ${TOTAL_RAM} GB"
echo "Used RAM  : ${USED_RAM} GB"
echo "Free RAM  : ${FREE_RAM} GB"
pass "RAM detected"

# ------------------------------------------------------------
info "System / BIOS Information"
SYS_VENDOR=$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null)
SYS_PRODUCT=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null)
BIOS_VENDOR=$(cat /sys/devices/virtual/dmi/id/bios_vendor 2>/dev/null)
BIOS_DATE=$(cat /sys/devices/virtual/dmi/id/bios_date 2>/dev/null)

echo "System Vendor : ${SYS_VENDOR:-Unknown}"
echo "System Model  : ${SYS_PRODUCT:-Unknown}"
echo "BIOS Vendor   : ${BIOS_VENDOR:-Unknown}"
echo "BIOS Date     : ${BIOS_DATE:-Unknown}"
manual "Motherboard / BIOS info may be hidden on VPS"

# ------------------------------------------------------------
info "Storage (Disk & Usage)"
lsblk -o NAME,MODEL,SIZE,ROTA,TYPE | while read -r line; do echo "$line"; done

if lsblk -o ROTA | grep -q "0"; then
  pass "SSD / NVMe storage detected"
else
  fail "Rotational disk (HDD) detected"
fi

df -h --output=source,size,used,avail,pcent,target | sed 1d
pass "Filesystem usage calculated"

# ------------------------------------------------------------
info "GPU Detection (not required for VPS)"
if command -v lspci &>/dev/null && lspci | grep -qi vga; then
  lspci | grep -i vga
  manual "GPU detected (not required for VPS)"
else
  manual "No GPU detected (normal for VPS)"
fi

# ------------------------------------------------------------
info "Virtual Machine Detection"
if grep -qi hypervisor /proc/cpuinfo; then
  pass "Virtualized environment detected"
else
  manual "Bare metal or hypervisor not exposed"
fi

# ------------------------------------------------------------
info "Basic Network & DNS"
timeout_cmd "ping -c 1 1.1.1.1 &>/dev/null" \
  && pass "Internet connectivity OK" \
  || fail "Internet connectivity failed"

timeout_cmd "ping -c 1 google.com &>/dev/null" \
  && pass "DNS resolution working" \
  || fail "DNS resolution failed"

# ------------------------------------------------------------
info "Public IP & Reverse DNS"
PUBLIC_IP=$(timeout_cmd "curl -fsS ifconfig.me/ip" || timeout_cmd "curl -fsS api.ipify.org")

if [[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Public IP: $PUBLIC_IP"
  pass "Public IP detected"
else
  manual "Public IP detection failed"
fi

PTR=$(timeout_cmd "dig -x $PUBLIC_IP +short")
[[ -n "$PTR" ]] && pass "Reverse DNS exists ($PTR)" || fail "No reverse DNS (PTR)"

# ------------------------------------------------------------
info "Outbound SMTP (CRITICAL)"
SMTP_OK=false
for target in smtp.gmail.com:587 smtp.gmail.com:465 gmail-smtp-in.l.google.com:25; do
  host=${target%:*}
  port=${target#*:}
  echo "Testing SMTP $host:$port"
  timeout_cmd "echo > /dev/tcp/$host/$port" &>/dev/null \
    && pass "SMTP port $port reachable" && SMTP_OK=true && break
done

$SMTP_OK || fail "All outbound SMTP ports blocked"

# ------------------------------------------------------------
info "Postfix (conditional)"
if $SMTP_OK && command -v postqueue &>/dev/null; then
  QUEUE=$(postqueue -p | tail -n +2)
  [[ -z "$QUEUE" ]] && pass "Postfix queue empty" || manual "Postfix queue not empty"
else
  manual "Postfix test skipped"
fi

# ------------------------------------------------------------
info "Outbound HTTPS & API Access"
timeout_cmd "curl -fsS https://api.github.com &>/dev/null" \
  && pass "Outbound HTTPS allowed" \
  || fail "Outbound HTTPS blocked"

# ------------------------------------------------------------
info "Docker / Container Readiness"
command -v docker &>/dev/null \
  && pass "Docker available" \
  || [[ -d /sys/fs/cgroup ]] \
     && pass "Kernel supports containers" \
     || manual "Container support unclear"

# ------------------------------------------------------------
echo -e "${BLUE}================ FINAL RESULT =================${RESET}"
echo "PASS   : $PASS"
echo "FAIL   : $FAIL"
echo "WARN   : $MANUAL"
echo "---------------------------------------------"

if [[ $FAIL -eq 0 && $PASS -ge 12 ]]; then
  echo -e "${GREEN}FINAL VERDICT: SAFE TO BUY & USE LONG-TERM${RESET}"
elif [[ $FAIL -le 2 ]]; then
  echo -e "${YELLOW}FINAL VERDICT: CONDITIONAL - REVIEW WARNINGS${RESET}"
else
  echo -e "${RED}FINAL VERDICT: DO NOT BUY THIS VPS${RESET}"
fi

echo "============================================================"
