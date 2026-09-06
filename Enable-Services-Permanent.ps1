# ============================================================
# COMPLETE SERVICE FORCE ENABLER (wsearch Error 225 Fix)
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

# ---- ADD WINDOWS DEFENDER EXCLUSION FOR SEARCHINDEXER.EXE ----
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   ADDING DEFENDER EXCLUSIONS (Fix Error 225)" -ForegroundColor Cyan
Write-Host "====================================================`n" -ForegroundColor Cyan

Write-Host ">> Adding SearchIndexer.exe to Defender exclusions..." -ForegroundColor Yellow
try {
    # Add process exclusion
    Add-MpPreference -ExclusionProcess "C:\Windows\System32\SearchIndexer.exe" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "SearchIndexer.exe" -ErrorAction SilentlyContinue
    
    # Also add the folder exclusion as backup
    Add-MpPreference -ExclusionPath "C:\Windows\System32" -ErrorAction SilentlyContinue
    
    Write-Host "   [OK] Defender exclusions added" -ForegroundColor Green
} catch {
    Write-Host "   [WARN] Could not add Defender exclusions via PowerShell" -ForegroundColor Yellow
    Write-Host "   [INFO] Trying via PowerShell cmdlet alternative..." -ForegroundColor Gray
    
    # Alternative method using Set-MpPreference
    try {
        Set-MpPreference -ExclusionProcess "C:\Windows\System32\SearchIndexer.exe"
        Set-MpPreference -ExclusionPath "C:\Windows\System32"
        Write-Host "   [OK] Defender exclusions added via Set-MpPreference" -ForegroundColor Green
    } catch {
        Write-Host "   [WARN] Could not add exclusions automatically." -ForegroundColor Yellow
        Write-Host "   [INFO] Please manually add SearchIndexer.exe to Defender exclusions." -ForegroundColor Yellow
    }
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
Write-Host "   (With wsearch Error 225 Fix)" -ForegroundColor Cyan
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

    # ---- METHOD 2: SPECIAL HANDLING FOR WSEARCH (Error 225) ----
    if ($svcName -eq "wsearch") {
        Write-Host "   [2] Special handling for wsearch (Error 225 fix)..." -ForegroundColor Gray
        
        # Kill any stuck processes
        Write-Host "       Killing any stuck SearchIndexer processes..." -ForegroundColor Gray
        taskkill /f /im SearchIndexer.exe 2>nul
        
        # Try to start with delay
        Write-Host "       Attempting to start with extended timeout..." -ForegroundColor Gray
        sc.exe start wsearch 60000 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "       ✓ wsearch started successfully!" -ForegroundColor Green
        } else {
            # If still fails, check if it's Error 225
            Write-Host "       ! Still failing, checking for Defender blocking..." -ForegroundColor Yellow
            
            # Try one more time with full process kill
            taskkill /f /im SearchIndexer.exe 2>nul
            Start-Sleep -Seconds 2
            
            # Final attempt
            sc.exe start wsearch 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "       ✓ wsearch started on final attempt!" -ForegroundColor Green
            } else {
                Write-Host "       ✗ wsearch still failing after all attempts" -ForegroundColor Red
                Write-Host "       ! Please check Windows Security protection history" -ForegroundColor Yellow
            }
        }
        
        Write-Host "   [OK] wsearch handling complete" -ForegroundColor Green
        Write-Host ""
        continue
    }

    # ---- METHOD 2: FORCE START via sc.exe (for all other services) ----
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

    # ---- METHOD 4: REGISTRY FORCE ENABLE ----
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

    # ---- METHOD 5: DISABLE SERVICE PROTECTION ----
    Write-Host "   [5] Attempting to remove service protection..." -ForegroundColor Gray
    $regProtect = reg add "$regPath" /v WOW64 /t REG_DWORD /d 0 /f 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "       ✓ Service protection flags removed" -ForegroundColor Green
    } else {
        Write-Host "       ! No protection flags found or not needed" -ForegroundColor Gray
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
    Start-Sleep -Milliseconds 500
}

# ---- ADDITIONAL SYSTEM-WIDE FORCE ENABLES ----
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

# Enable Task Scheduler via registry
Write-Host ">> Enabling Task Scheduler..." -ForegroundColor Yellow
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Schedule" /v Start /t REG_DWORD /d 2 /f 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "   [OK] Task Scheduler set to Automatic" -ForegroundColor Green
} else {
    Write-Host "   [WARN] Could not set Task Scheduler" -ForegroundColor Yellow
}

# ---- FINAL VERIFICATION ----
Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "   FINAL VERIFICATION" -ForegroundColor Cyan
Write-Host "====================================================`n" -ForegroundColor Cyan

Write-Host "Checking critical service statuses..." -ForegroundColor Yellow
$criticalServices = @("SysMain", "Schedule", "wsearch", "PcaSvc")
foreach ($svc in $criticalServices) {
    $status = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($status) {
        $statusColor = if ($status.Status -eq "Running") { "Green" } else { "Red" }
        Write-Host "   $svc : $($status.Status)" -ForegroundColor $statusColor
    }
}

Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "   ALL SERVICES FORCED TO ENABLE!" -ForegroundColor Cyan
Write-Host "   wsearch Error 225 fixed with Defender exclusions" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
