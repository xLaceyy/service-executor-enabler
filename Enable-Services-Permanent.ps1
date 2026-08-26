# ============================================================
# SERVICE ENABLER + PERMANENT RECOVERY (Never Shut)
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

Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "   ENABLING, STARTING & SETTING RECOVERY" -ForegroundColor Cyan
Write-Host "   (These services will NEVER stay stopped)" -ForegroundColor Cyan
Write-Host "====================================================`n" -ForegroundColor Cyan

foreach ($svcName in $services) {
    Write-Host ">> Processing: $svcName" -ForegroundColor Yellow

    # Check if service exists
    $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Host "   [SKIP] Service not found on this system." -ForegroundColor Gray
        Write-Host ""
        continue
    }

    # ---- 1. SET STARTUP TO AUTOMATIC (using sc.exe for reliability) ----
    $result = sc.exe config $svcName start= auto 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   [OK] Startup set to Automatic" -ForegroundColor Green
    } else {
        # DcomLaunch usually fails here because it's a Boot/System driver. That's expected.
        if ($svcName -eq "DcomLaunch") {
            Write-Host "   [INFO] DcomLaunch uses 'Boot' start type (higher than Automatic). Skipping change." -ForegroundColor Yellow
        } else {
            Write-Host "   [WARN] Could not set startup (may already be set or protected)." -ForegroundColor Yellow
        }
    }

    # ---- 2. START THE SERVICE IF NOT RUNNING ----
    if ($service.Status -ne "Running") {
        sc.exe start $svcName 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   [OK] Service started" -ForegroundColor Green
        } else {
            Write-Host "   [WARN] Could not start service" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   [OK] Already running" -ForegroundColor Green
    }

    # ---- 3. SET RECOVERY ACTIONS (The "Never Shut" part) ----
    # Reset=0 means the failure count never resets.
    # Actions: Restart after 60 seconds on 1st, 2nd, and subsequent failures.
    $recoveryResult = sc.exe failure $svcName reset= 0 actions= restart/60000/restart/60000/restart/60000 2>&1
    
    # Check if recovery setting succeeded.
    # Some protected services (like DcomLaunch) might lock this.
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   [OK] Recovery set: Will auto-restart if it crashes" -ForegroundColor Green
    } else {
        if ($svcName -eq "DcomLaunch") {
            Write-Host "   [INFO] DcomLaunch is kernel-protected. Recovery not required." -ForegroundColor Yellow
        } else {
            Write-Host "   [WARN] Could not set recovery (service may be protected)." -ForegroundColor Yellow
        }
    }

    Write-Host ""
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   ALL DONE!" -ForegroundColor Cyan
Write-Host "   If any of these services crash, Windows will" -ForegroundColor Cyan
Write-Host "   automatically restart them within 60 seconds." -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
