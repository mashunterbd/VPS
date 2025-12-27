# ============================================================
# VPS / SERVER PREFLIGHT INSPECTOR - WINDOWS (FINAL)
# Purpose: Full system inspection for buying & auditing
# ============================================================

$PASS = 0
$FAIL = 0
$WARN = 0

function Pass($m){ Write-Host "[PASS]  $m" -ForegroundColor Green;  $global:PASS++ }
function Fail($m){ Write-Host "[FAIL]  $m" -ForegroundColor Red;    $global:FAIL++ }
function Warn($m){ Write-Host "[WARN]  $m" -ForegroundColor Yellow; $global:WARN++ }
function Info($m){ Write-Host "`n==> $m" -ForegroundColor Cyan }
function Show($l,$v){ Write-Host ("    {0,-28}: {1}" -f $l,$v) }

Write-Host "============================================================"
Write-Host " VPS / SERVER PREFLIGHT INSPECTOR (WINDOWS)"
Write-Host " FINAL RECONCILED VERSION"
Write-Host "============================================================"
Write-Host "Scan started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# ------------------------------------------------------------
Info "System Information"
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem

Show "OS Name" $os.Caption
Show "OS Architecture" $os.OSArchitecture
Show "OS Build" $os.BuildNumber
Show "Computer Name" $cs.Name
Show "System Manufacturer" $cs.Manufacturer
Show "System Model" $cs.Model
Show "System Type" $cs.SystemType

$uptime = (Get-Date) - $os.LastBootUpTime
Show "Uptime" "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
Pass "System information collected"

# ------------------------------------------------------------
Info "Motherboard (BaseBoard)"
$board = Get-CimInstance Win32_BaseBoard
Show "Motherboard Brand" $board.Manufacturer
Show "Motherboard Model" $board.Product

if ($board.Manufacturer -match "OEM|Filled|Unknown") {
    Warn "Motherboard details partially hidden (normal on VPS)"
} else {
    Pass "Motherboard information detected"
}

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
    Warn "CPU virtualization not exposed"
}

if ($cs.Model -match "Virtual|VMware|KVM|Xen|HVM|QEMU|Hyper-V") {
    Pass "Virtual machine environment detected"
} else {
    Warn "Bare metal or hypervisor string hidden"
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

if ($totalRAM -ge 2) { Pass "RAM sufficient" }
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
Info "Graphics (GPU)"
$gpus = Get-CimInstance Win32_VideoController

if (!$gpus) {
    Warn "No GPU detected (normal for VPS)"
} else {
    foreach ($gpu in $gpus) {
        Show "GPU Model" $gpu.Name
        if ($gpu.AdapterRAM -and $gpu.AdapterRAM -gt 0) {
            $vramGB = [math]::Round($gpu.AdapterRAM/1GB,2)
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
Info "Network Adapters"
Get-CimInstance Win32_NetworkAdapter -Filter "NetEnabled=true" | ForEach-Object {
    Show "Adapter Name" $_.Name
    Show "MAC Address" $_.MACAddress
    if ($_.Speed) {
        Show "Link Speed" ("{0} Mbps" -f ($_.Speed/1MB))
    } else {
        Warn "Link speed not reported"
    }
}
Pass "Network adapters inspected"

# ------------------------------------------------------------
Info "DNS Configuration"
$dns = Get-DnsClientServerAddress -AddressFamily IPv4
foreach ($d in $dns) {
    Show "Interface" $d.InterfaceAlias
    Show "DNS Servers" ($d.ServerAddresses -join ", ")
}
Pass "DNS servers listed"

# ------------------------------------------------------------
Info "Connectivity Tests"
if (Test-Connection 1.1.1.1 -Count 1 -Quiet) { Pass "Internet connectivity OK" }
else { Fail "Internet connectivity failed" }

try {
    Resolve-DnsName google.com -ErrorAction Stop | Out-Null
    Pass "DNS resolution working"
} catch {
    Fail "DNS resolution failed"
}

# ------------------------------------------------------------
Info "Public IP & Reverse DNS"
$IP = $null
$sources = @(
  "https://ifconfig.me/ip",
  "https://api.ipify.org",
  "https://ipinfo.io/ip",
  "https://icanhazip.com"
)

foreach ($s in $sources) {
  try {
    $r = Invoke-WebRequest $s -UseBasicParsing -TimeoutSec 5
    if ($r.Content.Trim() -match '^\d{1,3}(\.\d{1,3}){3}$') {
        $IP = $r.Content.Trim()
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
    $ptr = Resolve-DnsName $IP -Type PTR -ErrorAction Stop
    Show "PTR Record" $ptr.NameHost
    Pass "Reverse DNS exists"
} catch {
    Fail "No reverse DNS (PTR)"
}

# ------------------------------------------------------------
Info "Outbound SMTP (CRITICAL)"
$smtpOK = $false
$ports = @(
 @{H="smtp.gmail.com";P=587},
 @{H="smtp.gmail.com";P=465},
 @{H="gmail-smtp-in.l.google.com";P=25}
)

foreach ($p in $ports) {
    if (Test-NetConnection $p.H -Port $p.P -InformationLevel Quiet) {
        Pass "SMTP port $($p.P) reachable"
        $smtpOK = $true
    } else {
        Warn "SMTP port $($p.P) blocked"
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

if ($FAIL -eq 0 -and $PASS -ge 18) {
    Write-Host "FINAL VERDICT: SAFE TO BUY & USE LONG-TERM" -ForegroundColor Green
} elseif ($FAIL -le 2) {
    Write-Host "FINAL VERDICT: CONDITIONAL - REVIEW WARNINGS" -ForegroundColor Yellow
} else {
    Write-Host "FINAL VERDICT: DO NOT BUY THIS SYSTEM" -ForegroundColor Red
}

Write-Host "Scan completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "============================================================"
