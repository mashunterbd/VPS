#!/usr/bin/env bash
# ============================================================
# VPS INFRASTRUCTURE PRE-FLIGHT CHECK
# Purpose : Decide if a VPS is SAFE for long-term usage
# Covers  : Email (Send/Receive), Web Hosting, Automation, n8n
# Design  : No silent skips, fallback logic, timeouts, progress
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

pass()   { echo -e "${GREEN}✔ PASS${RESET}  $1"; ((PASS++)); }
fail()   { echo -e "${RED}✖ FAIL${RESET}  $1"; ((FAIL++)); }
manual() { echo -e "${YELLOW}⚠ MANUAL${RESET} $1"; ((MANUAL++)); }
info()   { echo -e "${BLUE}▶${RESET} $1"; }

progress() {
  echo -ne "${BLUE}   → Working...${RESET}\r"
}

timeout_cmd() {
  timeout "$TIMEOUT" bash -c "$1"
}

echo -e "${BLUE}============================================================"
echo " VPS PRE-PURCHASE & POST-PURCHASE VERIFICATION TOOL"
echo "============================================================${RESET}"

# ------------------------------------------------------------
info "Detecting Operating System (compatibility check)"
OS="Unknown Linux"
command -v lsb_release &>/dev/null && OS=$(lsb_release -ds)
[[ -f /etc/os-release ]] && OS=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
echo "Detected OS: $OS"
pass "Operating system detected"

# ------------------------------------------------------------
info "Basic Network & DNS connectivity (required for everything)"
progress
timeout_cmd "ping -c 1 1.1.1.1 &>/dev/null" \
  && pass "ICMP internet connectivity OK" \
  || fail "No ICMP connectivity (network/firewall issue)"

progress
timeout_cmd "ping -c 1 google.com &>/dev/null" \
  && pass "DNS resolution working" \
  || fail "DNS resolution failed"

# ------------------------------------------------------------
info "Detecting Public IP & Reverse DNS (email reputation)"
PUBLIC_IP=$(timeout_cmd "curl -fsS ifconfig.me" || timeout_cmd "curl -fsS ipinfo.io/ip")

if [[ -n "$PUBLIC_IP" ]]; then
  echo "Public IP: $PUBLIC_IP"
  pass "Public IP detected"
else
  manual "Unable to auto-detect public IP"
fi

PTR=$(timeout_cmd "dig -x $PUBLIC_IP +short")
[[ -n "$PTR" ]] \
  && pass "Reverse DNS exists ($PTR)" \
  || fail "No reverse DNS (PTR) record"

# ------------------------------------------------------------
info "Outbound SMTP port availability (CRITICAL for email sending)"

SMTP_OK=false
SMTP_HOSTS=("smtp.gmail.com:587" "smtp.gmail.com:465" "gmail-smtp-in.l.google.com:25")

for target in "${SMTP_HOSTS[@]}"; do
  host=${target%:*}
  port=${target#*:}
  echo "Testing SMTP $host:$port"
  progress
  timeout_cmd "echo > /dev/tcp/$host/$port" &>/dev/null \
    && pass "Outbound SMTP $port reachable" && SMTP_OK=true && break \
    || echo "   → Timeout, trying next..."
done

$SMTP_OK || fail "All outbound SMTP ports blocked (25/587/465)"

# ------------------------------------------------------------
info "Third-party SMTP relay compatibility (Brevo, Mailgun, SES)"
RELAY_OK=false
RELAYS=("smtp-relay.brevo.com" "smtp.mailgun.org" "email-smtp.us-east-1.amazonaws.com")

for r in "${RELAYS[@]}"; do
  echo "Testing relay $r:587"
  progress
  timeout_cmd "echo > /dev/tcp/$r/587" &>/dev/null \
    && pass "SMTP relay reachable ($r)" && RELAY_OK=true && break \
    || echo "   → Relay unreachable, trying alternative..."
done

$RELAY_OK || manual "No external SMTP relay reachable (provider-level SMTP block likely)"

# ------------------------------------------------------------
info "Postfix mail system check (conditional logic applied)"

if $SMTP_OK; then
  if command -v postqueue &>/dev/null; then
    QUEUE=$(postqueue -p | tail -n +2)
    [[ -z "$QUEUE" ]] \
      && pass "Postfix mail queue empty" \
      || echo "$QUEUE" | grep -qi timeout \
         && fail "Postfix queue contains timeout errors" \
         || manual "Postfix queue not empty (manual review needed)"
  else
    manual "Postfix not installed (SMTP works, install later if needed)"
  fi
else
  manual "Postfix test skipped (SMTP ports blocked → install pointless)"
fi

# ------------------------------------------------------------
info "Outbound HTTPS & API access (WordPress, n8n, automation)"
progress
timeout_cmd "curl -fsS https://api.github.com &>/dev/null" \
  && pass "Outbound HTTPS & APIs allowed" \
  || fail "Outbound HTTPS blocked (automation will fail)"

# ------------------------------------------------------------
info "Latency & Geo-IP scoring (performance & region awareness)"
LAT_TARGETS=("1.1.1.1" "8.8.8.8" "9.9.9.9")
LAT_TOTAL=0
LAT_COUNT=0

for ip in "${LAT_TARGETS[@]}"; do
  RTT=$(timeout_cmd "ping -c 2 $ip" | awk -F'time=' '/time=/{sum+=$2;count++} END{if(count) print sum/count}')
  [[ -n "$RTT" ]] && LAT_TOTAL=$(echo "$LAT_TOTAL + $RTT" | bc) && ((LAT_COUNT++))
done

if [[ $LAT_COUNT -gt 0 ]]; then
  AVG_LAT=$(echo "$LAT_TOTAL / $LAT_COUNT" | bc)
  echo "Average latency: ${AVG_LAT} ms"
  (( $(echo "$AVG_LAT < 80" | bc -l) )) \
    && pass "Good global latency" \
    || manual "High latency (region-specific performance)"
else
  manual "Latency test failed (ICMP restricted)"
fi

COUNTRY=$(timeout_cmd "curl -fsS ipinfo.io/country")
[[ -n "$COUNTRY" ]] && echo "Server country: $COUNTRY" || manual "Geo-IP lookup failed"

# ------------------------------------------------------------
info "Disk type & performance (mail queue, DB, logs)"
if command -v lsblk &>/dev/null; then
  lsblk -o ROTA | grep -q "0" \
    && pass "SSD/NVMe storage detected" \
    || fail "Rotational disk detected (HDD)"
else
  manual "Disk type detection unavailable"
fi

# ------------------------------------------------------------
info "Container / n8n readiness"
command -v docker &>/dev/null \
  && pass "Docker available" \
  || [[ -d /sys/fs/cgroup ]] \
     && pass "Kernel supports containers (cgroups)" \
     || fail "Container support not detected"

# ------------------------------------------------------------
echo -e "${BLUE}================ FINAL RESULT =================${RESET}"
echo "PASS   : $PASS"
echo "FAIL   : $FAIL"
echo "MANUAL : $MANUAL"
echo "---------------------------------------------"

if [[ $FAIL -eq 0 && $PASS -ge 9 ]]; then
  echo -e "${GREEN}FINAL VERDICT: SAFE TO BUY & USE LONG-TERM${RESET}"
elif [[ $FAIL -le 2 ]]; then
  echo -e "${YELLOW}FINAL VERDICT: CONDITIONAL — REVIEW WARNINGS${RESET}"
else
  echo -e "${RED}FINAL VERDICT: DO NOT BUY THIS VPS${RESET}"
fi

echo "============================================================"
