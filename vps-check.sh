#!/usr/bin/env bash

# ============================================================
# VPS PRE-PURCHASE & POST-PURCHASE VERIFICATION SCRIPT
# Purpose: Detect VPS limitations BEFORE long-term usage
# Focus: Email (SMTP), Web Hosting, Automation, APIs, Security
# Compatible with: Ubuntu, Debian, CentOS, Rocky, Alma
# ============================================================

set +e

PASS_COUNT=0
FAIL_COUNT=0
MANUAL_COUNT=0

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
BLUE="\e[34m"
RESET="\e[0m"

pass()   { echo -e "${GREEN}✔ PASS${RESET}  $1"; ((PASS_COUNT++)); }
fail()   { echo -e "${RED}✖ FAIL${RESET}  $1"; ((FAIL_COUNT++)); }
manual() { echo -e "${YELLOW}⚠ MANUAL${RESET} $1"; ((MANUAL_COUNT++)); }

echo -e "${BLUE}"
echo "============================================================"
echo " VPS PRE-PURCHASE & POST-PURCHASE AUTOMATED CHECK"
echo "============================================================"
echo -e "${RESET}"

# ------------------------------------------------------------
echo -e "\n[1] SYSTEM & OS DETECTION (Why: compatibility & stability)"

if command -v lsb_release &>/dev/null; then
    OS=$(lsb_release -ds)
elif [ -f /etc/os-release ]; then
    OS=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
else
    OS="Unknown Linux"
fi

echo "Detected OS: $OS"
pass "Operating system detected"

# ------------------------------------------------------------
echo -e "\n[2] BASIC NETWORK CONNECTIVITY (Why: DNS & outbound traffic)"

ping -c 1 1.1.1.1 &>/dev/null \
  && pass "ICMP connectivity to internet (1.1.1.1)" \
  || fail "ICMP connectivity failed (possible firewall/network issue)"

ping -c 1 google.com &>/dev/null \
  && pass "DNS resolution works (google.com)" \
  || fail "DNS resolution failed"

# ------------------------------------------------------------
echo -e "\n[3] PUBLIC IP & rDNS PRECHECK (Why: email reputation)"

PUBLIC_IP=$(curl -fsS ifconfig.me 2>/dev/null || curl -fsS ipinfo.io/ip 2>/dev/null)

if [[ -n "$PUBLIC_IP" ]]; then
    echo "Public IP: $PUBLIC_IP"
    pass "Public IP detected"
else
    manual "Could not auto-detect public IP (check manually)"
fi

# ------------------------------------------------------------
echo -e "\n[4] OUTBOUND SMTP PORT CHECK (CRITICAL FOR EMAIL)"

SMTP_PASS=false

test_port() {
    local host=$1 port=$2
    timeout 5 bash -c "echo > /dev/tcp/$host/$port" &>/dev/null
}

declare -A SMTP_TESTS=(
  ["smtp.gmail.com"]=587
  ["smtp.gmail.com_alt"]=465
  ["gmail-smtp-in.l.google.com"]=25
)

for key in "${!SMTP_TESTS[@]}"; do
    host="${key%_alt}"
    port="${SMTP_TESTS[$key]}"
    echo "Testing outbound SMTP: $host:$port"
    if test_port "$host" "$port"; then
        pass "Outbound SMTP port $port reachable ($host)"
        SMTP_PASS=true
        break
    else
        echo "  -> Failed, trying next alternative..."
    fi
done

$SMTP_PASS || fail "All outbound SMTP ports blocked (25/587/465)"

# ------------------------------------------------------------
echo -e "\n[5] THIRD-PARTY SMTP RELAY COMPATIBILITY"

RELAYS=("smtp-relay.brevo.com" "smtp.mailgun.org" "email-smtp.us-east-1.amazonaws.com")
RELAY_OK=false

for r in "${RELAYS[@]}"; do
    echo "Testing relay: $r:587"
    if test_port "$r" 587; then
        pass "External SMTP relay reachable ($r)"
        RELAY_OK=true
        break
    fi
done

$RELAY_OK || manual "SMTP relay unreachable (provider-level SMTP block likely)"

# ------------------------------------------------------------
echo -e "\n[6] HTTPS & API ACCESS (Why: WordPress, n8n, integrations)"

curl -fsS https://api.github.com &>/dev/null \
  && pass "Outbound HTTPS & APIs allowed (GitHub API)" \
  || fail "Outbound HTTPS blocked (automation will fail)"

# ------------------------------------------------------------
echo -e "\n[7] FIREWALL CONTROL CHECK"

if command -v ufw &>/dev/null; then
    ufw status &>/dev/null \
      && pass "UFW firewall accessible (admin control)" \
      || manual "UFW exists but status unavailable"
elif command -v iptables &>/dev/null; then
    iptables -L &>/dev/null \
      && pass "iptables accessible (admin control)" \
      || manual "iptables exists but not readable"
else
    manual "No firewall tool detected"
fi

# ------------------------------------------------------------
echo -e "\n[8] DISK TYPE & PERFORMANCE (Why: mail queues, DB, logs)"

if command -v lsblk &>/dev/null; then
    if lsblk -o ROTA | grep -q "0"; then
        pass "SSD/NVMe storage detected"
    else
        fail "Rotational disk detected (HDD)"
    fi
else
    manual "lsblk not available (check disk type manually)"
fi

# ------------------------------------------------------------
echo -e "\n[9] DOCKER / CONTAINER READINESS (Why: n8n, modern stacks)"

if command -v docker &>/dev/null; then
    pass "Docker available"
elif [ -d /sys/fs/cgroup ]; then
    pass "Kernel supports containers (cgroups present)"
else
    fail "Container support not detected"
fi

# ------------------------------------------------------------
echo -e "\n================ FINAL EVALUATION ================="

echo "PASS:    $PASS_COUNT"
echo "FAIL:    $FAIL_COUNT"
echo "MANUAL:  $MANUAL_COUNT"
echo "--------------------------------------------------"

if [[ $FAIL_COUNT -eq 0 && $PASS_COUNT -ge 8 ]]; then
    echo -e "${GREEN}FINAL VERDICT: SAFE TO BUY & USE LONG-TERM${RESET}"
elif [[ $FAIL_COUNT -le 2 ]]; then
    echo -e "${YELLOW}FINAL VERDICT: CONDITIONAL (Review failed items)${RESET}"
else
    echo -e "${RED}FINAL VERDICT: DO NOT BUY THIS VPS${RESET}"
fi

echo "=================================================="
