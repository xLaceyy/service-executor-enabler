# ============================================================
# SERVICE STATUS VIEWER (Read-Only)
# Displays status of critical services without making changes
# ============================================================

$isAdmin = [System.Security.Principal.WindowsPrincipal]::new(
    [System.Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    Write-Host "`n⚠️  Running as Administrator - viewing only, no changes made" -ForegroundColor Yellow
} else {
    Write-Host "`nℹ️  Running as standard user - viewing only" -ForegroundColor Gray
}

# ---- GET SYSTEM INFO ----
Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "   SYSTEM SERVICE STATUS VIEWER" -ForegroundColor Cyan
Write-Host "====================================================`n" -ForegroundColor Cyan

# System uptime
$uptime = (Get-Date) - (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
Write-Host "SYSTEM UPTIME:" -ForegroundColor Yellow
Write-Host "  Last Boot: $((Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime)" -ForegroundColor Gray
Write-Host "  Uptime: $($uptime.Days) days, $($uptime.Hours) hours, $($uptime.Minutes) minutes" -ForegroundColor Gray
Write-Host ""

# ---- SERVICES TO CHECK ----
$services = @(
    @{Name="SysMain"; Display="SysMain (SuperFetch)"},
    @{Name="PcaSvc"; Display="Program Compatibility Assistant"},
    @{Name="DPS"; Display="Diagnostic Policy Service"},
    @{Name="EventLog"; Display="Windows Event Log"},
    @{Name="Schedule"; Display="Task Scheduler"},
    @{Name="Bam"; Display="Background Activity Moderator"},
    @{Name="Dusmsvc"; Display="Data Usage Service"},
    @{Name="Appinfo"; Display="Application Information"},
    @{Name="CDPSvc"; Display="Connected Devices Platform"},
    @{Name="DcomLaunch"; Display="DCOM Server Process Launcher"},
    @{Name="PlugPlay"; Display="Plug and Play"},
    @{Name="wsearch"; Display="Windows Search"},
    @{Name="WSearchIdxPi"; Display="Windows Search Indexer"}
)

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   SERVICE STATUS" -ForegroundColor Cyan
Write-Host "====================================================`n" -ForegroundColor Cyan

# ---- DISPLAY SERVICE STATUSES ----
$running = 0
$stopped = 0
$notFound = 0

foreach ($svc in $services) {
    $svcName = $svc.Name
    $display = $svc.Display
    
    $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    
    if ($service) {
        $status = $service.Status
        $startType = $service.StartType
        
        # Color code the status
        if ($status -eq "Running") {
            $statusColor = "Green"
            $running++
        } elseif ($status -eq "StartPending") {
            $statusColor = "Yellow"
            $stopped++
        } elseif ($status -eq "StopPending") {
            $statusColor = "Yellow"
            $stopped++
        } else {
            $statusColor = "Red"
            $stopped++
        }
        
        Write-Host "  $display" -ForegroundColor White
        Write-Host "    Status: " -NoNewline
        Write-Host "$status" -ForegroundColor $statusColor
        Write-Host "    Start Type: $startType" -ForegroundColor Gray
        Write-Host ""
    } else {
        Write-Host "  $display" -ForegroundColor White
        Write-Host "    Status: " -NoNewline
        Write-Host "NOT FOUND" -ForegroundColor DarkGray
        $notFound++
        Write-Host ""
    }
}

# ---- SUMMARY ----
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   SUMMARY" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  Running:  " -NoNewline
Write-Host "$running" -ForegroundColor Green
Write-Host "  Stopped:  " -NoNewline
Write-Host "$stopped" -ForegroundColor Red
Write-Host "  Not Found:" -NoNewline
Write-Host "$notFound" -ForegroundColor Gray

# ---- CHECK PREFETCH STATUS ----
Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "   PREFETCH STATUS" -ForegroundColor Cyan
Write-Host "====================================================`n" -ForegroundColor Cyan

# Check Prefetch folder
$prefetchPath = "C:\Windows\Prefetch"
if (Test-Path $prefetchPath) {
    $pfCount = (Get-ChildItem "$prefetchPath\*.pf" -File -ErrorAction SilentlyContinue).Count
    Write-Host "  Prefetch Files: " -NoNewline
    if ($pfCount -gt 0) {
        Write-Host "$pfCount files" -ForegroundColor Green
    } else {
        Write-Host "0 files (Prefetch might be disabled)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Prefetch folder not found" -ForegroundColor Red
}

# Check Prefetch registry settings
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"
try {
    $enablePrefetcher = (Get-ItemProperty -Path $regPath -Name "EnablePrefetcher" -ErrorAction SilentlyContinue).EnablePrefetcher
    if ($enablePrefetcher -eq 3) {
        Write-Host "  EnablePrefetcher: " -NoNewline
        Write-Host "3 (Full - Enabled)" -ForegroundColor Green
    } elseif ($enablePrefetcher -eq 2) {
        Write-Host "  EnablePrefetcher: " -NoNewline
        Write-Host "2 (Boot Only)" -ForegroundColor Yellow
    } elseif ($enablePrefetcher -eq 1) {
        Write-Host "  EnablePrefetcher: " -NoNewline
        Write-Host "1 (Application Only)" -ForegroundColor Yellow
    } elseif ($enablePrefetcher -eq 0) {
        Write-Host "  EnablePrefetcher: " -NoNewline
        Write-Host "0 (Disabled)" -ForegroundColor Red
    } else {
        Write-Host "  EnablePrefetcher: Not set (default: 3)" -ForegroundColor Gray
    }
} catch {
    Write-Host "  EnablePrefetcher: Registry key not found" -ForegroundColor Gray
}

# Check SysMain status
$sysMain = Get-Service -Name "SysMain" -ErrorAction SilentlyContinue
if ($sysMain) {
    Write-Host "  SysMain (SuperFetch): " -NoNewline
    if ($sysMain.Status -eq "Running") {
        Write-Host "Running ✓" -ForegroundColor Green
    } else {
        Write-Host "Stopped ✗" -ForegroundColor Red
    }
}

Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "   VIEWING COMPLETE" -ForegroundColor Cyan
Write-Host "   No changes were made to the system" -ForegroundColor Gray
Write-Host "====================================================" -ForegroundColor Cyan
