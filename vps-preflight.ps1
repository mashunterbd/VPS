# ============================================================
# VPS PREFLIGHT CHECK - WINDOWS (FINAL CLEAN VERSION)
# Purpose : Decide if a VPS / Server is safe for long-term use
# ============================================================

$PASS = 0
$FAIL = 0
$WARN = 0

function Pass($m){ Write-Host "[PASS]  $m" -ForegroundColor Green;  $global:PASS++ }
function Fail($m){ Write-Host "[FAIL]  $m" -ForegroundColor Red;    $global:FAIL++ }
function Warn($m){ Write-Host "[WARN]  $m" -ForegroundColor Yellow; $global:WARN++ }
function Info($m){ Write-Host "`n==> $m" -ForegroundColor Cyan }

Write-Host "============================================================"
Write-Host " VPS PRE-PURCHASE & POST-PURCHASE CHECK (WINDOWS)"
Write-Host "============================================================"

# ------------------------------------------------------------
Info "Operating System"
$os = Get-CimInstance Win32_OperatingSystem
Write-Host "OS: $($os.Caption) ($($os.OSArchitecture))"
Pass "Operating system detected"

# ------------------------------------------------------------
Info "CPU & Virtualization"
$cpu = Get-CimInstance Win32_Processor
Write-Host "CPU Model : $($cpu.Name)"
Write-Host "Cores     : $($cpu.NumberOfCores)"
Write-Host "Threads   : $($cpu.NumberOfLogicalProcessors)"

if ($cpu.VirtualizationFirmwareEnabled) {
    Pass "CPU virtualization enabled"
} else {
    Warn "CPU virtualization not exposed"
}

# ------------------------------------------------------------
Info "Memory (RAM)"
$totalRAM = [Math]::Round($os.TotalVisibleMemorySize / 1MB,2)
$freeRAM  = [Math]::Round($os.FreePhysicalMemory / 1MB,2)
$usedRAM  = [Math]::Round($totalRAM - $freeRAM,2)

Write-Host "Total RAM : $totalRAM GB"
Write-Host "Used RAM  : $usedRAM GB"
Write-Host "Free RAM  : $freeRAM GB"
Pass "RAM detected"

# ------------------------------------------------------------
Info "Motherboard Information (best-effort)"
$board = Get-CimInstance Win32_BaseBoard
Write-Host "Board Manufacturer : $($board.Manufacturer)"
Write-Host "Board Model        : $($board.Product)"
Warn "Motherboard generation/date not required for VPS decision"

# ------------------------------------------------------------
Info "Storage & Disk Usage"
Get-CimInstance Win32_DiskDrive | ForEach-Object {
    Write-Host "Disk Model : $($_.Model)"
    Write-Host "Disk Size  : $([Math]::Round($_.Size / 1GB,2)) GB"
}

Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $usedPct = [Math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100,2)
    Write-Host "Volume $($_.DeviceID) : $usedPct% used"
}
Pass "Storage detected & usage calculated"

# ------------------------------------------------------------
Info "Graphics (GPU - not required for VPS)"
Get-CimInstance Win32_VideoController | ForEach-Object {
    Write-Host "GPU Model : $($_.Name)"
    if ($_.AdapterRAM) {
        Write-Host "GPU RAM   : $([Math]::Round($_.AdapterRAM / 1GB,2)) GB"
    }
}
Warn "Dedicated GPU not required for VPS workloads"

# ------------------------------------------------------------
Info "Network & DNS Connectivity"
if (Test-Connection 1.1.1.1 -Count 1 -Quiet) {
    Pass "Internet connectivity OK"
} else {
    Fail "Internet connectivity failed"
}

try {
    Resolve-DnsName google.com -ErrorAction Stop | Out-Null
    Pass "DNS resolution working"
} catch {
    Fail "DNS resolution failed"
}

# ------------------------------------------------------------
Info "Public IP & Reverse DNS"
$IP = $null
$ipSources = @(
    "https://ifconfig.me/ip",
    "https://api.ipify.org",
    "https://ipinfo.io/ip"
)

foreach ($src in $ipSources) {
    try {
        $resp = Invoke-WebRequest -Uri $src -UseBasicParsing -TimeoutSec 5
        $candidate = $resp.Content.Trim()
        if ($candidate -match '^\d{1,3}(\.\d{1,3}){3}$') {
            $IP = $candidate
            break
        }
    } catch {}
}

if ($IP) {
    Write-Host "Public IP: $IP"
    Pass "Public IP detected"
} else {
    Fail "Public IP detection failed"
}

try {
    Resolve-DnsName $IP -Type PTR -ErrorAction Stop | Out-Null
    Pass "Reverse DNS (PTR) exists"
} catch {
    Fail "No reverse DNS (PTR)"
}

# ------------------------------------------------------------
Info "Outbound SMTP (CRITICAL)"
$smtpOK = $false
$targets = @(
    @{H="smtp.gmail.com";P=587},
    @{H="smtp.gmail.com";P=465},
    @{H="gmail-smtp-in.l.google.com";P=25}
)

foreach ($t in $targets) {
    if (Test-NetConnection $t.H -Port $t.P -InformationLevel Quiet) {
        Pass "SMTP port $($t.P) reachable"
        $smtpOK = $true
        break
    }
}

if (-not $smtpOK) {
    Fail "All outbound SMTP ports blocked"
}

# ------------------------------------------------------------
Info "Docker / Container Readiness"
if (Get-Command docker -ErrorAction SilentlyContinue) {
    Pass "Docker available"
} else {
    Warn "Docker not installed"
}

# ------------------------------------------------------------
Write-Host "================ FINAL RESULT ================="
Write-Host "PASS   : $PASS"
Write-Host "FAIL   : $FAIL"
Write-Host "WARN   : $WARN"
Write-Host "---------------------------------------------"

if ($FAIL -eq 0 -and $PASS -ge 10) {
    Write-Host "FINAL VERDICT: SAFE TO BUY & USE LONG-TERM" -ForegroundColor Green
} elseif ($FAIL -le 2) {
    Write-Host "FINAL VERDICT: CONDITIONAL - REVIEW WARNINGS" -ForegroundColor Yellow
} else {
    Write-Host "FINAL VERDICT: DO NOT BUY THIS VPS" -ForegroundColor Red
}

Write-Host "============================================================"
