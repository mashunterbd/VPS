# ============================================================
# VPS PREFLIGHT CHECK - WINDOWS (ENHANCED + FIXED)
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
Write-Host " Enhanced Edition (Stable)"
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

if ($cs.Model -match "Virtual|VMware|KVM|Xen|HVM|QEMU") {
    Pass "Running inside virtualized environment"
} else {
    Warn "Bare metal or hypervisor not exposed"
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
Info "Network Connectivity"
$hosts = @("1.1.1.1","8.8.8.8","208.67.222.222")
$ok = 0
foreach($h in $hosts){ if(Test-Connection $h -Count 1 -Quiet){$ok++} }

if ($ok -eq $hosts.Count) { Pass "Internet connectivity excellent" }
elseif ($ok -gt 0) { Warn "Partial internet connectivity" }
else { Fail "Internet connectivity failed" }

# ------------------------------------------------------------
Info "DNS Resolution"
$domains = @("google.com","github.com","cloudflare.com")
$dnsOK = 0
foreach($d in $domains){
    try{ Resolve-DnsName $d -ErrorAction Stop | Out-Null; $dnsOK++ }catch{}
}

if ($dnsOK -eq $domains.Count) { Pass "DNS resolution working" }
elseif ($dnsOK -gt 0) { Warn "Partial DNS resolution" }
else { Fail "DNS resolution failed" }

# ------------------------------------------------------------
Info "Public IP & Reverse DNS"
$IP = $null
$sources = @(
  "https://ifconfig.me/ip",
  "https://api.ipify.org",
  "https://ipinfo.io/ip",
  "https://icanhazip.com"
)

foreach($s in $sources){
  try{
    $r = Invoke-WebRequest $s -UseBasicParsing -TimeoutSec 5
    if ($r.Content.Trim() -match '^\d{1,3}(\.\d{1,3}){3}$'){
        $IP = $r.Content.Trim(); break
    }
  }catch{}
}

if ($IP){
  Show "Public IP" $IP
  Pass "Public IP detected"
}else{
  Fail "Public IP detection failed"
}

try{
  $ptr = Resolve-DnsName $IP -Type PTR -ErrorAction Stop
  Show "PTR Record" $ptr.NameHost
  Pass "Reverse DNS exists"
}catch{
  Fail "No reverse DNS (PTR)"
}

# ------------------------------------------------------------
Info "Critical Outbound Ports"
$ports = @(
 @{N="HTTP";H="google.com";P=80},
 @{N="HTTPS";H="google.com";P=443},
 @{N="SMTP 587";H="smtp.gmail.com";P=587},
 @{N="SMTP 465";H="smtp.gmail.com";P=465},
 @{N="SMTP 25";H="gmail-smtp-in.l.google.com";P=25}
)

$smtpOK = $false
foreach($p in $ports){
  if(Test-NetConnection $p.H -Port $p.P -InformationLevel Quiet){
    Pass "$($p.N) reachable"
    if($p.N -like "SMTP*"){ $smtpOK=$true }
  }else{
    Warn "$($p.N) blocked"
  }
}

if(-not $smtpOK){ Fail "All outbound SMTP ports blocked" }

# ------------------------------------------------------------
Info "Firewall & Security"
try{
  Get-NetFirewallProfile | ForEach-Object{
    Show "$($_.Name) Firewall" ("Enabled: {0}" -f $_.Enabled)
  }
  Pass "Firewall status checked"
}catch{
  Warn "Firewall status unavailable"
}

# ------------------------------------------------------------
Info "Final Summary"
Show "PASS" $PASS
Show "FAIL" $FAIL
Show "WARN" $WARN

if ($FAIL -eq 0 -and $PASS -ge 15){
  Write-Host "`nFINAL VERDICT: SAFE TO BUY & USE LONG-TERM" -ForegroundColor Green
}elseif ($FAIL -le 2){
  Write-Host "`nFINAL VERDICT: CONDITIONAL - REVIEW WARNINGS" -ForegroundColor Yellow
}else{
  Write-Host "`nFINAL VERDICT: DO NOT BUY THIS VPS" -ForegroundColor Red
}

Write-Host "`nScan completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "============================================================"
