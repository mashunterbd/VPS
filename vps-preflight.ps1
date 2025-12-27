# ============================================================
# VPS PREFLIGHT CHECK - WINDOWS (ENHANCED VERSION)
# Purpose: Comprehensive VPS/Server evaluation for purchase
# ============================================================

$PASS = 0
$FAIL = 0
$WARN = 0

function Pass($m){ Write-Host "[PASS]  $m" -ForegroundColor Green;  $global:PASS++ }
function Fail($m){ Write-Host "[FAIL]  $m" -ForegroundColor Red;    $global:FAIL++ }
function Warn($m){ Write-Host "[WARN]  $m" -ForegroundColor Yellow; $global:WARN++ }
function Info($m){ Write-Host "`n==> $m" -ForegroundColor Cyan }
function Data($label, $value){ Write-Host "    $label : $value" -ForegroundColor White }

Write-Host "============================================================" -ForegroundColor Magenta
Write-Host " VPS PRE-PURCHASE & POST-PURCHASE CHECK (WINDOWS)" -ForegroundColor Magenta
Write-Host " Enhanced Edition v2.0" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "Scan started at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"

# ------------------------------------------------------------
Info "System Information"
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
Data "OS Name" "$($os.Caption)"
Data "OS Architecture" "$($os.OSArchitecture)"
Data "OS Build" "$($os.BuildNumber)"
Data "Computer Name" "$($cs.Name)"
Data "Manufacturer" "$($cs.Manufacturer)"
Data "Model" "$($cs.Model)"
Data "System Type" "$($cs.SystemType)"
Data "Boot Time" "$($os.LastBootUpTime)"
$uptime = (Get-Date) - $os.LastBootUpTime
Data "Uptime" "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
Pass "System information collected"

# ------------------------------------------------------------
Info "CPU & Virtualization Details"
$cpu = Get-CimInstance Win32_Processor
Data "CPU Model" "$($cpu.Name)"
Data "Manufacturer" "$($cpu.Manufacturer)"
Data "Cores" "$($cpu.NumberOfCores)"
Data "Logical Processors" "$($cpu.NumberOfLogicalProcessors)"
Data "Max Clock Speed" "$($cpu.MaxClockSpeed) MHz"
Data "Current Clock Speed" "$($cpu.CurrentClockSpeed) MHz"
Data "L2 Cache Size" "$($cpu.L2CacheSize) KB"
Data "L3 Cache Size" "$($cpu.L3CacheSize) KB"

if ($cpu.VirtualizationFirmwareEnabled) {
    Pass "CPU virtualization enabled (nested virtualization possible)"
} else {
    Warn "CPU virtualization not exposed (expected on most VPS)"
}

# Check if running in VM
$hypervisor = Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty Model
if ($hypervisor -match "Virtual|VMware|HVM|KVM|Xen|QEMU") {
    Data "Hypervisor Type" "$hypervisor"
    Pass "Running in virtualized environment (as expected for VPS)"
} else {
    Warn "Does not appear to be virtualized (check if this is bare metal)"
}

# ------------------------------------------------------------
Info "Memory (RAM) Analysis"
$totalRAM = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
$freeRAM = [Math]::Round($os.FreePhysicalMemory / 1MB, 2)
$usedRAM = [Math]::Round($totalRAM - $freeRAM, 2)
$usedPct = [Math]::Round(($usedRAM / $totalRAM) * 100, 2)

Data "Total RAM" "$totalRAM GB"
Data "Used RAM" "$usedRAM GB ($usedPct%)"
Data "Free RAM" "$freeRAM GB"
Data "Available RAM" "$([Math]::Round($os.FreePhysicalMemory / 1MB, 2)) GB"

if ($totalRAM -ge 2) {
    Pass "Adequate RAM for VPS operations ($totalRAM GB)"
} elseif ($totalRAM -ge 1) {
    Warn "Low RAM detected ($totalRAM GB) - may limit workloads"
} else {
    Fail "Insufficient RAM ($totalRAM GB) - too low for modern workloads"
}

# ------------------------------------------------------------
Info "Storage Analysis"
$diskCount = 0
Get-CimInstance Win32_DiskDrive | ForEach-Object {
    $diskCount++
    Data "Disk $diskCount Model" "$($_.Model)"
    Data "Disk $diskCount Size" "$([Math]::Round($_.Size / 1GB, 2)) GB"
    Data "Disk $diskCount Interface" "$($_.InterfaceType)"
    Data "Disk $diskCount Status" "$($_.Status)"
}
Pass "Physical disk information collected"

Write-Host ""
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $totalSize = [Math]::Round($_.Size / 1GB, 2)
    $freeSize = [Math]::Round($_.FreeSpace / 1GB, 2)
    $usedSize = [Math]::Round($totalSize - $freeSize, 2)
    $usedPct = [Math]::Round(($usedSize / $totalSize) * 100, 2)
    
    Data "Volume $($_.DeviceID) Total" "$totalSize GB"
    Data "Volume $($_.DeviceID) Used" "$usedSize GB ($usedPct%)"
    Data "Volume $($_.DeviceID) Free" "$freeSize GB"
    Data "Volume $($_.DeviceID) FS" "$($_.FileSystem)"
    
    if ($usedPct -gt 90) {
        Fail "Volume $($_.DeviceID) critically full ($usedPct%)"
    } elseif ($usedPct -gt 80) {
        Warn "Volume $($_.DeviceID) getting full ($usedPct%)"
    } else {
        Pass "Volume $($_.DeviceID) has adequate space"
    }
}

# ------------------------------------------------------------
Info "Network Adapters"
Get-CimInstance Win32_NetworkAdapter -Filter "NetEnabled='True'" | ForEach-Object {
    Data "Adapter" "$($_.Name)"
    Data "Status" "$($_.NetConnectionStatus)"
    Data "Speed" "$($_.Speed)"
}
Pass "Network adapter information collected"

# ------------------------------------------------------------
Info "Internet Connectivity Tests"
$testHosts = @("1.1.1.1", "8.8.8.8", "208.67.222.222")
$successCount = 0

foreach ($host in $testHosts) {
    if (Test-Connection $host -Count 1 -Quiet) {
        $successCount++
    }
}

if ($successCount -eq $testHosts.Count) {
    Pass "Internet connectivity excellent (all test hosts reachable)"
} elseif ($successCount -gt 0) {
    Warn "Internet connectivity partial ($successCount/$($testHosts.Count) hosts reachable)"
} else {
    Fail "Internet connectivity failed (no test hosts reachable)"
}

# ------------------------------------------------------------
Info "DNS Resolution Tests"
$dnsTests = @("google.com", "cloudflare.com", "github.com")
$dnsSuccess = 0

foreach ($domain in $dnsTests) {
    try {
        Resolve-DnsName $domain -ErrorAction Stop | Out-Null
        $dnsSuccess++
    } catch {}
}

if ($dnsSuccess -eq $dnsTests.Count) {
    Pass "DNS resolution working perfectly"
} elseif ($dnsSuccess -gt 0) {
    Warn "DNS resolution partial ($dnsSuccess/$($dnsTests.Count) domains resolved)"
} else {
    Fail "DNS resolution completely failed"
}

# DNS Server Check
$dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object {$_.ServerAddresses.Count -gt 0}
if ($dnsServers) {
    Data "DNS Servers" "$($dnsServers.ServerAddresses -join ', ')"
    Pass "DNS servers configured"
} else {
    Fail "No DNS servers configured"
}

# ------------------------------------------------------------
Info "Public IP & Geolocation"
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
    Data "Public IP" "$IP"
    Pass "Public IP detected successfully"
    
    # Get IP geolocation info
    try {
        $ipInfo = Invoke-RestMethod -Uri "https://ipinfo.io/$IP/json" -TimeoutSec 5
        Data "IP Location" "$($ipInfo.city), $($ipInfo.region), $($ipInfo.country)"
        Data "IP Organization" "$($ipInfo.org)"
        Data "IP Timezone" "$($ipInfo.timezone)"
        Pass "IP geolocation data retrieved"
    } catch {
        Warn "Could not retrieve IP geolocation data"
    }
} else {
    Fail "Public IP detection failed (connectivity issue?)"
}

# ------------------------------------------------------------
Info "Reverse DNS (PTR Record)"
if ($IP) {
    try {
        $ptr = Resolve-DnsName $IP -Type PTR -ErrorAction Stop
        Data "PTR Record" "$($ptr.NameHost)"
        Pass "Reverse DNS (PTR) exists - good for email reputation"
    } catch {
        Fail "No reverse DNS (PTR) - may affect email deliverability"
    }
}

# ------------------------------------------------------------
Info "Critical Port Tests (Outbound)"
$portTests = @(
    @{Name="HTTP"; Host="www.google.com"; Port=80},
    @{Name="HTTPS"; Host="www.google.com"; Port=443},
    @{Name="SMTP (587)"; Host="smtp.gmail.com"; Port=587},
    @{Name="SMTP (465)"; Host="smtp.gmail.com"; Port=465},
    @{Name="SMTP (25)"; Host="gmail-smtp-in.l.google.com"; Port=25},
    @{Name="SSH"; Host="github.com"; Port=22},
    @{Name="MySQL"; Host="127.0.0.1"; Port=3306},
    @{Name="PostgreSQL"; Host="127.0.0.1"; Port=5432}
)

$smtpOK = $false
foreach ($test in $portTests) {
    try {
        $result = Test-NetConnection $test.Host -Port $test.Port -InformationLevel Quiet -WarningAction SilentlyContinue
        if ($result) {
            Pass "$($test.Name) port $($test.Port) reachable"
            if ($test.Name -like "SMTP*") { $smtpOK = $true }
        } else {
            if ($test.Name -like "SMTP*") {
                Warn "$($test.Name) port $($test.Port) blocked"
            } elseif ($test.Name -in @("MySQL", "PostgreSQL")) {
                Info "    $($test.Name) port $($test.Port) not accessible (service may not be installed)"
            } else {
                Fail "$($test.Name) port $($test.Port) blocked"
            }
        }
    } catch {
        Warn "Could not test $($test.Name) port $($test.Port)"
    }
}

if (-not $smtpOK) {
    Fail "ALL outbound SMTP ports blocked - cannot send email"
}

# ------------------------------------------------------------
Info "Firewall Status"
try {
    $fwProfiles = Get-NetFirewallProfile
    foreach ($profile in $fwProfiles) {
        Data "$($profile.Name) Profile" "Enabled: $($profile.Enabled)"
    }
    Pass "Firewall status checked"
} catch {
    Warn "Could not check firewall status"
}

# ------------------------------------------------------------
Info "Software & Services Check"
$software = @(
    @{Name="Docker"; Command="docker"},
    @{Name="Git"; Command="git"},
    @{Name="Python"; Command="python"},
    @{Name="Node.js"; Command="node"},
    @{Name="PowerShell Core"; Command="pwsh"}
)

foreach ($sw in $software) {
    if (Get-Command $sw.Command -ErrorAction SilentlyContinue) {
        $version = & $sw.Command --version 2>$null
        Data "$($sw.Name)" "Installed ($version)"
        Pass "$($sw.Name) available"
    } else {
        Info "    $($sw.Name) not installed"
    }
}

# ------------------------------------------------------------
Info "Windows Updates Status"
try {
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $searchResult = $updateSearcher.Search("IsInstalled=0")
    
    if ($searchResult.Updates.Count -eq 0) {
        Pass "Windows updates are current (no pending updates)"
    } else {
        Warn "$($searchResult.Updates.Count) Windows updates pending"
    }
} catch {
    Warn "Could not check Windows Update status"
}

# ------------------------------------------------------------
Info "Performance Counters"
try {
    $cpuLoad = Get-Counter '\Processor(_Total)\% Processor Time' | Select-Object -ExpandProperty CounterSamples | Select-Object -ExpandProperty CookedValue
    $cpuLoad = [Math]::Round($cpuLoad, 2)
    Data "Current CPU Usage" "$cpuLoad%"
    
    if ($cpuLoad -lt 50) {
        Pass "CPU load is normal ($cpuLoad%)"
    } elseif ($cpuLoad -lt 80) {
        Warn "CPU load is moderate ($cpuLoad%)"
    } else {
        Fail "CPU load is high ($cpuLoad%)"
    }
} catch {
    Warn "Could not measure CPU load"
}

# ------------------------------------------------------------
Info "Security & Best Practices"
# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Pass "Script running with Administrator privileges"
} else {
    Warn "Not running as Administrator (some checks may be limited)"
}

# Check Windows Defender status
try {
    $defenderStatus = Get-MpComputerStatus -ErrorAction Stop
    if ($defenderStatus.AntivirusEnabled) {
        Pass "Windows Defender antivirus is enabled"
    } else {
        Warn "Windows Defender antivirus is disabled"
    }
} catch {
    Warn "Could not check Windows Defender status"
}

# ------------------------------------------------------------
Write-Host "`n============================================================" -ForegroundColor Magenta
Write-Host " FINAL RESULTS" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta
Data "Total PASS" "$PASS"
Data "Total FAIL" "$FAIL"
Data "Total WARN" "$WARN"
Write-Host "------------------------------------------------------------"

# Decision Logic
$score = $PASS - ($FAIL * 2) - ($WARN * 0.5)
$maxScore = $PASS + $FAIL + $WARN

if ($FAIL -eq 0 -and $PASS -ge 15) {
    Write-Host "`n✓ FINAL VERDICT: SAFE TO BUY & USE LONG-TERM" -ForegroundColor Green
    Write-Host "  This VPS meets all critical requirements." -ForegroundColor Green
} elseif ($FAIL -le 1 -and $PASS -ge 10) {
    Write-Host "`n⚠ FINAL VERDICT: CONDITIONAL - REVIEW WARNINGS" -ForegroundColor Yellow
    Write-Host "  This VPS is acceptable but has minor issues." -ForegroundColor Yellow
} elseif ($FAIL -le 3) {
    Write-Host "`n⚠ FINAL VERDICT: USE WITH CAUTION" -ForegroundColor Yellow
    Write-Host "  This VPS has some issues that may affect functionality." -ForegroundColor Yellow
} else {
    Write-Host "`n✗ FINAL VERDICT: DO NOT BUY THIS VPS" -ForegroundColor Red
    Write-Host "  This VPS has critical issues." -ForegroundColor Red
}

Write-Host "`nScan completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "============================================================`n" -ForegroundColor Magenta
