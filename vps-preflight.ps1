# ============================================================
# VPS PREFLIGHT CHECK - WINDOWS (REFINED VERSION)
# Purpose : Decide if a VPS is SAFE for long-term use
# Output  : Clean, ASCII-safe, professional
# ============================================================

$PASS = 0
$FAIL = 0
$MANUAL = 0

function Pass($msg)   { Write-Host "[PASS]  $msg" -ForegroundColor Green;  $global:PASS++ }
function Fail($msg)   { Write-Host "[FAIL]  $msg" -ForegroundColor Red;    $global:FAIL++ }
function Manual($msg) { Write-Host "[WARN]  $msg" -ForegroundColor Yellow; $global:MANUAL++ }
function Info($msg)   { Write-Host "`n==> $msg" -ForegroundColor Cyan }

Write-Host "============================================================"
Write-Host " VPS PRE-PURCHASE & POST-PURCHASE CHECK (WINDOWS)"
Write-Host "============================================================"

# ------------------------------------------------------------
Info "Operating System Detection (compatibility check)"
$os = Get-CimInstance Win32_OperatingSystem
Write-Host "Detected OS: $($os.Caption)"
Pass "Operating system detected"

# ------------------------------------------------------------
Info "Basic Network & DNS Connectivity"
if (Test-Connection 1.1.1.1 -Count 1 -Quiet) {
    Pass "ICMP internet connectivity OK"
} else {
    Fail "No ICMP connectivity (network or firewall issue)"
}

try {
    Resolve-DnsName google.com -ErrorAction Stop | Out-Null
    Pass "DNS resolution working"
} catch {
    Fail "DNS resolution failed"
}

# ------------------------------------------------------------
Info "Public IP & Reverse DNS (email reputation)"

$IP = $null
$IpSources = @(
    "https://ifconfig.me/ip",
    "https://api.ipify.org",
    "https://ipinfo.io/ip"
)

foreach ($src in $IpSources) {
    try {
        Write-Host "Trying IP source: $src"
        $resp = Invoke-WebRequest -Uri $src -UseBasicParsing -TimeoutSec 5
        $candidate = $resp.Content.Trim()
        if ($candidate -match '^\d{1,3}(\.\d{1,3}){3}$') {
            $IP = $candidate
            break
        }
    } catch {
        Write-Host "  -> Failed, trying next source..."
    }
}

if ($IP) {
    Write-Host "Public IP: $IP"
    Pass "Public IP detected (clean text)"
} else {
    Manual "Unable to auto-detect public IP (manual check required)"
}

try {
    Resolve-DnsName $IP -Type PTR -ErrorAction Stop | Out-Null
    Pass "Reverse DNS (PTR) exists"
} catch {
    Fail "No reverse DNS (PTR) record"
}

# ------------------------------------------------------------
Info "Outbound SMTP Port Availability (CRITICAL)"
$SMTP_OK = $false
$SMTP_Targets = @(
    @{Host="smtp.gmail.com"; Port=587},
    @{Host="smtp.gmail.com"; Port=465},
    @{Host="gmail-smtp-in.l.google.com"; Port=25}
)

foreach ($t in $SMTP_Targets) {
    Write-Host "Testing SMTP $($t.Host):$($t.Port)"
    if (Test-NetConnection $t.Host -Port $t.Port -InformationLevel Quiet) {
        Pass "Outbound SMTP port $($t.Port) reachable"
        $SMTP_OK = $true
        break
    } else {
        Write-Host "  -> Timeout, trying next..."
    }
}

if (-not $SMTP_OK) {
    Fail "All outbound SMTP ports blocked (25/587/465)"
}

# ------------------------------------------------------------
Info "External SMTP Relay Compatibility"
$Relays = @(
    "smtp-relay.brevo.com",
    "smtp.mailgun.org",
    "email-smtp.us-east-1.amazonaws.com"
)

$Relay_OK = $false
foreach ($r in $Relays) {
    Write-Host "Testing relay $r:587"
    if (Test-NetConnection $r -Port 587 -InformationLevel Quiet) {
        Pass "SMTP relay reachable ($r)"
        $Relay_OK = $true
        break
    } else {
        Write-Host "  -> Relay unreachable, trying alternative..."
    }
}

if (-not $Relay_OK) {
    Manual "No external SMTP relay reachable (provider-level SMTP block likely)"
}

# ------------------------------------------------------------
Info "Outbound HTTPS & API Access (automation readiness)"
try {
    Invoke-WebRequest https://api.github.com -UseBasicParsing -TimeoutSec 5 | Out-Null
    Pass "Outbound HTTPS & APIs allowed"
} catch {
    Fail "Outbound HTTPS blocked (automation will fail)"
}

# ------------------------------------------------------------
Info "Latency & Geo-IP Scoring"
$Targets = @("1.1.1.1","8.8.8.8","9.9.9.9")
$Times = @()

foreach ($ip in $Targets) {
    $ping = Test-Connection $ip -Count 2 -ErrorAction SilentlyContinue
    if ($ping) {
        $avg = ($ping | Measure-Object -Property ResponseTime -Average).Average
        $Times += $avg
    }
}

if ($Times.Count -gt 0) {
    $AvgLatency = [Math]::Round(($Times | Measure-Object -Average).Average,2)
    Write-Host "Average latency: $AvgLatency ms"
    if ($AvgLatency -lt 80) {
        Pass "Good global latency"
    } else {
        Manual "High latency (region-specific performance)"
    }
} else {
    Manual "Latency test failed (ICMP restricted)"
}

try {
    $Country = Invoke-WebRequest https://ipinfo.io/country -UseBasicParsing -TimeoutSec 5
    Write-Host "Server country: $($Country.Content.Trim())"
} catch {
    Manual "Geo-IP lookup failed"
}

# ------------------------------------------------------------
Info "Docker / Container Readiness"
if (Get-Command docker -ErrorAction SilentlyContinue) {
    Pass "Docker available"
} else {
    Manual "Docker not installed (can be installed later)"
}

# ------------------------------------------------------------
Write-Host "================ FINAL RESULT ================="
Write-Host "PASS   : $PASS"
Write-Host "FAIL   : $FAIL"
Write-Host "MANUAL : $MANUAL"
Write-Host "---------------------------------------------"

if ($FAIL -eq 0 -and $PASS -ge 8) {
    Write-Host "FINAL VERDICT: SAFE TO BUY & USE LONG-TERM" -ForegroundColor Green
} elseif ($FAIL -le 2) {
    Write-Host "FINAL VERDICT: CONDITIONAL - REVIEW WARNINGS" -ForegroundColor Yellow
} else {
    Write-Host "FINAL VERDICT: DO NOT BUY THIS VPS" -ForegroundColor Red
}

Write-Host "============================================================"
