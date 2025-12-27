# ============================================================
# VPS PREFLIGHT CHECK - WINDOWS (ENHANCED + GPU COMPLETE)
# Purpose: Comprehensive VPS/Server evaluation for purchase
# ============================================================

$PASS = 0
$FAIL = 0
$WARN = 0

function Pass($m){ Write-Host "[PASS]  $m" -ForegroundColor Green;  $global:PASS++ }
function Fail($m){ Write-Host "[FAIL]  $m" -ForegroundColor Red;    $global:FAIL++ }
function Warn($m){ Write-Host "[WARN]  $m" -ForegroundColor Yellow; $global:WARN++ }
function Info($m){ Write-Host "`n==> $m" -ForegroundColor Cyan }
function Show($l,$v){ Write-Host ("    {0,-25}: {1}" -f $l,$v) }

Write-Host "============================================================"
Write-Host " VPS PRE-PURCHASE & POST-PURCHASE CHECK (WINDOWS)"
Write-Host " Enhanced Edition (Stable + GPU)"
Write-Host "============================================================"
Write-Host "Scan started at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# ------------------------------------------------------------
Info "System Information"
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem

Show "OS Name" $os.Caption
Show "OS Architecture" $os.OSArchitecture
Show "OS Build" $os.BuildNumber
Show "Computer Name" $cs.Name
Show "Manufacturer" $cs.Manufacturer
Show "Model" $cs.Model
Show "System Type" $cs.SystemType

$uptime = (Get-Date) - $os.LastBootUpTime
Show "Uptime" "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
Pass "System information collected"

# ------------------------------------------------------------
Info "CPU & Virtualization"
$cpu = Get-CimInstance Win32_Processor
Show "CPU Model" $cpu.Name
Show "Cores" $cpu.NumberOfCores
Show "Logical CPUs" $cpu.NumberOfLogicalProcessors
Show "Max Clock" "$($cpu.MaxClockSpeed) MHz"
Show "L3 Cache" "$($cpu.L3CacheSize) KB"

if ($cpu.VirtualizationFirmwareEnabled) {
    Pass "CPU virtualization enabled"
} else {
    Warn "CPU virtualization not exposed (normal on VPS)"
}

# ------------------------------------------------------------
Info "Memory (RAM)"
$totalRAM = [math]::Round($os.TotalVisibleMemorySize/1MB,2)
$freeRAM  = [math]::Round($os.FreePhysicalMemory/1MB,2)
$usedRAM  = [math]::Round($totalRAM - $freeRAM,2)
$usedPct  = [math]::Round(($usedRAM/$totalRAM)*100,2)

Show "Total RAM" "$totalRAM GB"
Show "Used RAM" "$usedRAM GB ($usedPct%)"
Show "Free RAM" "$freeRAM GB"

if ($totalRAM -ge 2) { Pass "RAM sufficient for VPS" }
elseif ($totalRAM -ge 1) { Warn "Low RAM ($totalRAM GB)" }
else { Fail "Insufficient RAM ($totalRAM GB)" }

# ------------------------------------------------------------
Info "Storage"
Get-CimInstance Win32_DiskDrive | ForEach-Object {
    Show "Disk Model" $_.Model
    Show "Disk Size" ("{0} GB" -f [math]::Round($_.Size/1GB,2))
}

Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $used = [math]::Round((($_.Size-$_.FreeSpace)/$_.Size)*100,2)
    Show "Volume $($_.DeviceID)" "$used% used"
    if ($used -gt 90) { Fail "Disk $($_.DeviceID) critically full" }
    elseif ($used -gt 80) { Warn "Disk $($_.DeviceID) getting full" }
    else { Pass "Disk $($_.DeviceID) usage healthy" }
}

# ------------------------------------------------------------
Info "Graphics (GPU Detection)"
$gpus = Get-CimInstance Win32_VideoController

if ($gpus.Count -eq 0) {
    Warn "No GPU detected (normal for most VPS)"
} else {
    foreach ($gpu in $gpus) {
        Show "GPU Model" $gpu.Name

        if ($gpu.AdapterRAM -and $gpu.AdapterRAM -gt 0) {
            $vramGB = [math]::Round($gpu.AdapterRAM / 1GB,2)
            Show "GPU Memory" "$vramGB GB"
        } else {
            Show "GPU Memory" "Not reported"
        }

        if ($gpu.Name -match "NVIDIA|AMD|Radeon") {
            Pass "Dedicated GPU detected"
        } elseif ($gpu.Name -match "Intel") {
            Warn "Integrated GPU detected"
        } else {
            Warn "Unknown GPU type"
        }
    }
}

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
    "https://ipinfo.io/ip",
    "https://icanhazip.com"
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
    Show "Public IP" $IP
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
Show "PASS" $PASS
Show "FAIL" $FAIL
Show "WARN" $WARN
Write-Host "---------------------------------------------"

if ($FAIL -eq 0 -and $PASS -ge 15) {
    Write-Host "FINAL VERDICT: SAFE TO BUY & USE LONG-TERM" -ForegroundColor Green
} elseif ($FAIL -le 2) {
    Write-Host "FINAL VERDICT: CONDITIONAL - REVIEW WARNINGS" -ForegroundColor Yellow
} else {
    Write-Host "FINAL VERDICT: DO NOT BUY THIS VPS" -ForegroundColor Red
}

Write-Host "Scan completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "============================================================"
