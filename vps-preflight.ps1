# ============================================================
# VPS PREFLIGHT CHECK - WINDOWS (FULL SYSTEM VERSION)
# Purpose : Decide if a VPS is SAFE for long-term usage
# Includes: Hardware, Storage, Network, SMTP, Automation
# ============================================================

$PASS = 0
$FAIL = 0
$MANUAL = 0

function Pass($msg)   { Write-Host "[PASS]  $msg" -ForegroundColor Green;  $global:PASS++ }
function Fail($msg)   { Write-Host "[FAIL]  $msg" -ForegroundColor Red;    $global:FAIL++ }
function Warn($msg)   { Write-Host "[WARN]  $msg" -ForegroundColor Yellow; $global:MANUAL++ }
function Info($msg)   { Write-Host "`n==> $msg" -ForegroundColor Cyan }

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

$virt = $cpu.VirtualizationFirmwareEnabled
if ($virt -eq $true) {
    Pass "CPU virtualization enabled"
} else {
    Warn "CPU virtualization not exposed or disabled"
}

# ------------------------------------------------------------
Info "Memory (RAM)"
$totalRAM = [Math]::Round($os.TotalVisibleMemorySize / 1MB,2)
$freeRAM  = [Math]::Round($os.FreePhysicalMemory / 1MB,2)
$usedRAM  = [Math]::Round($totalRAM - $freeRAM,2)

Write-Host "Total RAM : $totalRAM GB"
Write-Host "Used RAM  : $usedRAM GB"
Write-Host "Free RAM  : $freeRAM GB"

Pass "RAM detected successfully"

# ------------------------------------------------------------
Info "Motherboard & BIOS"
$board = Get-CimInstance Win32_BaseBoard
$bios  = Get-CimInstance Win32_BIOS

Write-Host "Board Manufacturer : $($board.Manufacturer)"
Write-Host "Board Model        : $($board.Product)"
Write-Host "BIOS Vendor        : $($bios.Manufacturer)"
Write-Host "BIOS Year          : $($bios.ReleaseDate.Substring(0,4))"

Warn "Motherboard generation often hidden on VPS"

# ------------------------------------------------------------
Info "Storage (Disk & Usage)"
$disks = Get-CimInstance Win32_DiskDrive
foreach ($d in $disks) {
    Write-Host "Disk Model : $($d.Model)"
    Write-Host "Disk Size  : $([Math]::Round($d.Size / 1GB,2)) GB"
    if ($d.MediaType) {
        Write-Host "Disk Type  : $($d.MediaType)"
    } else {
        Warn "Disk type not exposed (likely virtual disk)"
    }
}

$vol = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
foreach ($v in $vol) {
    $size = [Math]::Round($v.Size / 1GB,2)
    $free = [Math]::Round($v.FreeSpace / 1GB,2)
    $used = [Math]::Round((($size - $free) / $size) * 100,2)

    Write-Host "Volume $($v.DeviceID) : $used% used, $free GB free"
}

Pass "Storage detected & usage calculated"

# ------------------------------------------------------------
Info "Graphics (GPU)"
$gpu = Get-CimInstance Win32_VideoController
foreach ($g in $gpu) {
    Write-Host "GPU Model : $($g.Name)"
    if ($g.AdapterRAM) {
        Write-Host "GPU RAM   : $([Math]::Round($g.AdapterRAM / 1GB,2)) GB"
    } else {
        Warn "GPU memory not exposed"
    }
}

Warn "Dedicated GPU not required for VPS workloads"

# ------------------------------------------------------------
Info "Virtual Machine Detection"
$cs = Get-CimInstance Win32_ComputerSystem
Write-Host "System Manufacturer : $($cs.Manufacturer)"
Write-Host "System Model        : $($cs.Model)"

if ($cs.Model -match "Virtual|KVM|VMware|Hyper-V") {
    Pass "Virtual machine environment detected"
} else {
    Warn "Bare metal or unknown virtualization"
}

# ------------------------------------------------------------
Info "Network & DNS Connectivity"
if (Test-Connection 1.1.1.1 -Count 1 -Quiet) {
    Pass "Internet connectivity OK"
} else {
    Fail "Internet connectivity failed"
}

try {
    Resolve-DnsName google.com | Out-Null
    Pass "DNS resolution working"
} catch {
    Fail "DNS resolution failed"
}

# ------------------------------------------------------------
Info "Public IP & Reverse DNS"
$IP = $null
$IpSources = @(
    "https://ifconfig.me/ip",
    "https://api.ipify.org",
    "https://ipinfo.io/ip"
)

foreach ($src in $IpSources) {
    try {
        $resp = Invoke-WebRequest $src -UseBasicParsing -TimeoutSec 5
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
    Warn "Public IP detection failed"
}

try {
    Resolve-DnsName $IP -Type PTR | Out-Null
    Pass "Reverse DNS (PTR) exists"
} catch {
    Fail "No reverse DNS (PTR)"
}

# ------------------------------------------------------------
Info "Outbound SMTP (CRITICAL)"
$SMTP_OK = $false
$targets = @(
    @{Host="smtp.gmail.com"; Port=587},
    @{Host="smtp.gmail.com"; Port=465},
    @{Host="gmail-smtp-in.l.google.com"; Port=25}
)

foreach ($t in $targets) {
    if (Test-NetConnection $t.Host -Port $t.Port -InformationLevel Quiet) {
        Pass "SMTP port $($t.Port) reachable"
        $SMTP_OK = $true
        break
    }
}

if (-not $SMTP_OK) {
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
Write-Host "WARN   : $MANUAL"
Write-Host "---------------------------------------------"

if ($FAIL -eq 0 -and $PASS -ge 12) {
    Write-Host "FINAL VERDICT: SAFE TO BUY & USE LONG-TERM" -ForegroundColor Green
} elseif ($FAIL -le 2) {
    Write-Host "FINAL VERDICT: CONDITIONAL - REVIEW WARNINGS" -ForegroundColor Yellow
} else {
    Write-Host "FINAL VERDICT: DO NOT BUY THIS VPS" -ForegroundColor Red
}

Write-Host "============================================================"
