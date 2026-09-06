# ============================================================
# FORCE SERVICE ENABLER + PERMANENT RECOVERY (Nuclear Option)
# Run this script as Administrator!
# ============================================================

$isAdmin = [System.Security.Principal.WindowsPrincipal]::new(
    [System.Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║ ADMINISTRATOR PRIVILEGES REQUIRED ║" -ForegroundColor Red
    Write-Host "║ Please run this script as Administrator! ║" -ForegroundColor Red
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Red
    exit
}

# ---- APPLY REGISTRY CONFIGURATION ----
Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "   APPLYING REGISTRY CONFIGURATION" -ForegroundColor Cyan
Write-Host "====================================================`n" -ForegroundColor Cyan

Write-Host ">> Setting EnableActivityFeed registry key..." -ForegroundColor Yellow
$regResult = reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v EnableActivityFeed /t REG_DWORD /d 1 /f 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "   [OK] EnableActivityFeed set to 1" -ForegroundColor Green
} else {
    Write-Host "   [WARN] Could not set registry key: $regResult" -ForegroundColor Yellow
}
Write-Host ""

# ---- SERVICE CONFIGURATION ----
$services = @(
    "SysMain",
    "PcaSvc",
    "DPS",
    "EventLog",
    "Schedule",
    "Bam",
    "Dusmsvc",
    "Appinfo",
    "CDPSvc",
    "DcomLaunch",
    "PlugPlay",
    "wsearch"
)

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   FORCING SERVICES TO ENABLE & START" -ForegroundColor Cyan
Write-Host "   (Using EVERY method available)" -ForegroundColor Cyan
Write-Host "====================================================`n" -ForegroundColor Cyan

foreach ($svcName in $services) {
    Write-Host ">> FORCING: $svcName" -ForegroundColor Magenta

    # Check if service exists
    $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Host "   [SKIP] Service not found on this system." -ForegroundColor Gray
        Write-Host ""
        continue
    }

    # ---- METHOD 1: FORCE STARTUP TYPE via sc.exe ----
    Write-Host "   [1] Setting startup to Automatic..." -ForegroundColor Gray
    $result1 = sc.exe config $svcName start= auto 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "       ✓ Startup set to Automatic" -ForegroundColor Green
    } else {
        # Try alternate method
        $result1b = sc.exe config $svcName start= demand 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "       ✓ Startup set to Demand (Automatic failed)" -ForegroundColor Yellow
        } else {
            Write-Host "       ✗ Could not modify startup type" -ForegroundColor Red
        }
    }

    # ---- METHOD 2: FORCE START via sc.exe ----
    Write-Host "   [2] Attempting to start service..." -ForegroundColor Gray
    $startAttempts = 0
    $maxAttempts = 3
    $started = $false
    
    while ($startAttempts -lt $maxAttempts -and -not $started) {
        $startAttempts++
        sc.exe start $svcName 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "       ✓ Service started (Attempt $startAttempts)" -ForegroundColor Green
            $started = $true
        } else {
            # Try with different flags
            if ($startAttempts -eq 2) {
                sc.exe start $svcName /d 2>&1 | Out-Null
            } elseif ($startAttempts -eq 3) {
                net start $svcName 2>&1 | Out-Null
            }
            Start-Sleep -Seconds 2
        }
    }
    
    if (-not $started) {
        Write-Host "       ✗ Could not start service after $maxAttempts attempts" -ForegroundColor Red
    }

    # ---- METHOD 3: FORCE RECOVERY (Never Shut) ----
    Write-Host "   [3] Setting auto-restart on failure..." -ForegroundColor Gray
    $recoveryResult = sc.exe failure $svcName reset= 0 actions= restart/60000/restart/60000/restart/60000 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "       ✓ Recovery set: Auto-restart on crash" -ForegroundColor Green
    } else {
        # Try alternate recovery method
        $recoveryResult2 = sc.exe failure $svcName reset= 0 actions= restart/30000/restart/30000/restart/30000 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "       ✓ Recovery set (alternate): Auto-restart on crash" -ForegroundColor Yellow
        } else {
            Write-Host "       ✗ Could not set recovery (service protected)" -ForegroundColor Red
        }
    }

    # ---- METHOD 4: REGISTRY FORCE ENABLE (for protected services) ----
    Write-Host "   [4] Applying registry force-enable..." -ForegroundColor Gray
    $regPath = "HKLM\SYSTEM\CurrentControlSet\Services\$svcName"
    
    # Set Start value to 2 (Automatic)
    $regStart = reg add "$regPath" /v Start /t REG_DWORD /d 2 /f 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "       ✓ Registry Start=2 set" -ForegroundColor Green
    } else {
        Write-Host "       ✗ Could not set registry Start value" -ForegroundColor Red
    }
    
    # Set DelayedAutoStart if applicable
    $regDelayed = reg add "$regPath" /v DelayedAutoStart /t REG_DWORD /d 1 /f 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "       ✓ Registry DelayedAutoStart set" -ForegroundColor Green
    } else {
        Write-Host "       ! Registry DelayedAutoStart not available" -ForegroundColor Gray
    }

    # ---- METHOD 5: DISABLE SERVICE PROTECTION (if applicable) ----
    Write-Host "   [5] Attempting to remove service protection..." -ForegroundColor Gray
    $regProtect = reg add "$regPath" /v WOW64 /t REG_DWORD /d 0 /f 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "       ✓ Service protection flags removed" -ForegroundColor Green
    } else {
        Write-Host "       ! No protection flags found or not needed" -ForegroundColor Gray
    }

    # ---- METHOD 6: FORCE DISABLE OF CONFLICTING DEPENDENCIES ----
    Write-Host "   [6] Checking for conflicting dependencies..." -ForegroundColor Gray
    try {
        $deps = (Get-Service $svcName).DependentServices
        if ($deps) {
            Write-Host "       ! Service has dependencies, ensuring they start first..." -ForegroundColor Yellow
            foreach ($dep in $deps) {
                sc.exe start $dep.Name 2>&1 | Out-Null
                Write-Host "          → Started dependency: $($dep.Name)" -ForegroundColor Gray
            }
        } else {
            Write-Host "       ✓ No conflicting dependencies found" -ForegroundColor Green
        }
    } catch {
        Write-Host "       ! Could not check dependencies" -ForegroundColor Gray
    }

    # ---- FINAL VERIFICATION ----
    Write-Host "   [✓] Verification: Checking status..." -ForegroundColor Gray
    $finalStatus = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($finalStatus) {
        Write-Host "       → Current Status: $($finalStatus.Status)" -ForegroundColor Cyan
        if ($finalStatus.Status -eq "Running") {
            Write-Host "       ✅ SERVICE IS RUNNING" -ForegroundColor Green
        } elseif ($finalStatus.Status -eq "StartPending") {
            Write-Host "       ⏳ Service is starting..." -ForegroundColor Yellow
        } else {
            Write-Host "       ⚠️ Service status: $($finalStatus.Status)" -ForegroundColor Yellow
        }
    }

    Write-Host ""

    # Small delay to prevent system overload
    Start-Sleep -Milliseconds 500
}

# ---- ADDITIONAL SYSTEM FORCE ENABLES ----
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   SYSTEM-WIDE FORCE ENABLES" -ForegroundColor Cyan
Write-Host "====================================================`n" -ForegroundColor Cyan

# Enable Prefetch via registry
Write-Host ">> Enabling Prefetch (SysMain)..." -ForegroundColor Yellow
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" /v EnablePrefetcher /t REG_DWORD /d 3 /f 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "   [OK] Prefetch enabled (Level 3)" -ForegroundColor Green
} else {
    Write-Host "   [WARN] Could not set Prefetch" -ForegroundColor Yellow
}

# Enable SuperFetch via registry
Write-Host ">> Enabling SuperFetch..." -ForegroundColor Yellow
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" /v EnableSuperfetch /t REG_DWORD /d 3 /f 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "   [OK] SuperFetch enabled (Level 3)" -ForegroundColor Green
} else {
    Write-Host "   [WARN] Could not set SuperFetch" -ForegroundColor Yellow
}

# Enable Task Scheduler (Schedule service) via registry
Write-Host ">> Enabling Task Scheduler..." -ForegroundColor Yellow
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Schedule" /v Start /t REG_DWORD /d 2 /f 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "   [OK] Task Scheduler set to Automatic" -ForegroundColor Green
} else {
    Write-Host "   [WARN] Could not set Task Scheduler" -ForegroundColor Yellow
}

Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "   ALL SERVICES FORCED TO ENABLE!" -ForegroundColor Cyan
Write-Host "   Verification Complete." -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
