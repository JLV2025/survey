<#
.SYNOPSIS
  Survey System  --  IIS deployment (Windows Server 2022 + IIS + ASP.NET 4.8)

.DESCRIPTION
  Full deployment pipeline:
  1. Install IIS + Windows Auth + ASP.NET 4.8 features (idempotent)
  2. Resolve port 80 conflicts (stop/remove Default Web Site if present)
  3. Remove old Survey site + app pool (if exists)
  4. Clean ASP.NET temporary cache
  5. Create app pool (.NET 4.0, Integrated, AlwaysRunning)
  6. Create IIS site
  7. Configure Windows Integrated Authentication
  8. Initialize or restore data
  9. Health check

.PARAMETER Mode
  Fresh   --  New install, create empty data/config if absent
  Update  --  Preserve data, restore from backup directory

.PARAMETER BackupDir
  Path to backup directory containing survey.json and/or config.json (Update mode)

.PARAMETER Port
  Binding port, default 80

.PARAMETER SiteName
  IIS site name, default "Survey"

.EXAMPLE
  .\setup-iis.ps1 -Mode Fresh

.EXAMPLE
  .\setup-iis.ps1 -Mode Update -BackupDir "C:\Temp\backup"
#>

param(
    [ValidateSet('Fresh', 'Update')]
    [string]$Mode = 'Fresh',

    [string]$BackupDir = '',

    [ValidateRange(1, 65535)]
    [int]$Port = 80,

    [string]$SiteName = 'Survey'
)

$ErrorActionPreference = 'Stop'
$host.UI.RawUI.WindowTitle = "Survey  --  Deploy ($Mode)"

# ============================================================
# Helpers
# ============================================================

function Write-Step {
    param([int]$Num, [int]$Total, [string]$Text)
    Write-Host "`n=== [$Num/$Total] $Text ===" -ForegroundColor Cyan
}

function Write-OK {
    Write-Host "  OK" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Msg)
    Write-Host "  WARN: $Msg" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Msg)
    Write-Host "  ERROR: $Msg" -ForegroundColor Red
}

$SitePath = $PSScriptRoot
$DataDir = Join-Path $SitePath 'data'
$ConfigPath = Join-Path $SitePath 'config.json'
$appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
$TotalSteps = if ($Mode -eq 'Update') { 7 } else { 6 }

# ============================================================
# Main
# ============================================================

Write-Host '========================================'
Write-Host "  Survey System  --  Deploy ($Mode)"
Write-Host "  Site : $SiteName"
Write-Host "  Path : $SitePath"
Write-Host "  Port : $Port"
Write-Host '========================================'

# ---- 1: IIS Features ----
Write-Step 1 $TotalSteps 'Install IIS + Windows Auth + ASP.NET 4.8'

$features = @(
    'Web-Server',
    'Web-Asp-Net45',
    'Web-Net-Ext45',
    'Web-ISAPI-Ext',
    'Web-ISAPI-Filter',
    'Web-Windows-Auth',
    'Web-Default-Doc',
    'Web-Static-Content',
    'Web-Filtering',
    'Web-Mgmt-Console',
    'Web-Scripting-Tools'
)

try {
    $result = Install-WindowsFeature -Name $features -ErrorAction Stop
    if ($result.RestartNeeded -eq 'Yes') {
        Write-Warn 'Server restart required after deployment'
    }
    $failed = $result | Where-Object { -not $_.Success }
    if ($failed) {
        Write-Warn "Some features failed: $($failed.Name -join ', ')"
    } else {
        Write-OK
    }
} catch {
    Write-Warn "Install-WindowsFeature failed: $_"
    Write-Host '  Ensure admin rights and WSUS/Windows Update reachable'
}

# ---- 2: Resolve port 80 conflicts ----
Write-Step 2 $TotalSteps 'Resolve port binding'

Import-Module IISAdministration -ErrorAction SilentlyContinue
if (-not (Get-Module IISAdministration)) {
    Import-Module WebAdministration -ErrorAction Stop
}

$portConflict = Get-IISSite -ErrorAction SilentlyContinue | Where-Object {
    $_.Bindings -match ':\d+:' | ForEach-Object {
        $b = $_.Bindings
    }
}
# Re-query properly
$existingSites = Get-IISSite -ErrorAction SilentlyContinue
$conflictSite = $null
foreach ($site in $existingSites) {
    foreach ($binding in $site.Bindings) {
        if ($binding.BindingInformation -eq "*:$($Port):") {
            $conflictSite = $site
            break
        }
    }
    if ($conflictSite) { break }
}

if ($conflictSite) {
    if ($conflictSite.Name -eq $SiteName) {
        Write-Host "  Existing $SiteName site found on port $Port  --  will be replaced"
    } elseif ($conflictSite.Name -eq 'Default Web Site') {
        Write-Host "  Default Web Site occupies port $Port  --  stopping and removing..."
        Stop-IISSite -Name 'Default Web Site' -Confirm:$false -ErrorAction SilentlyContinue
        Remove-IISSite -Name 'Default Web Site' -Confirm:$false -ErrorAction SilentlyContinue
        Write-OK
    } else {
        Write-Err "Port $Port occupied by '$($conflictSite.Name)'. Stop/remove it first, or use -Port to pick another."
        exit 1
    }
} else {
    Write-Host "  Port $Port is free"
    Write-OK
}

# ---- 3: Clear old Survey site + pool ----
Write-Step 3 $TotalSteps 'Remove old Survey site and app pool'

# Stop + delete site
$oldSite = Get-IISSite -Name $SiteName -ErrorAction SilentlyContinue
if ($oldSite) {
    Write-Host "  Stopping $SiteName site..."
    Stop-IISSite -Name $SiteName -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep 1
    Remove-IISSite -Name $SiteName -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep 1
    Write-Host "  Site removed"
}

# Delete app pool
Import-Module WebAdministration -ErrorAction SilentlyContinue
if (Test-Path "IIS:\AppPools\$SiteName") {
    Remove-WebAppPool -Name $SiteName -ErrorAction SilentlyContinue
    Start-Sleep 1
    Write-Host "  App pool removed"
}

Write-OK

# ---- 4: Clean ASP.NET temp cache ----
Write-Step 4 $TotalSteps 'Clean ASP.NET temporary cache'

$tempPaths = @(
    "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\Temporary ASP.NET Files",
    "$env:SystemRoot\Microsoft.NET\Framework\v4.0.30319\Temporary ASP.NET Files"
)

foreach ($tp in $tempPaths) {
    if (Test-Path $tp) {
        try {
            Get-ChildItem -Path $tp -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-Host "  Cleaned: $tp"
        } catch {
            Write-Warn "Failed to clean $tp : $_"
        }
    }
}

Write-OK

# ---- 5: Create app pool + site ----
Write-Step 5 $TotalSteps 'Create app pool and site'

# App pool
if (-not (Get-Module WebAdministration)) {
    Import-Module WebAdministration -ErrorAction Stop
}

New-WebAppPool -Name $SiteName -Force
Set-ItemProperty -Path "IIS:\AppPools\$SiteName" -Name managedRuntimeVersion -Value 'v4.0'
Set-ItemProperty -Path "IIS:\AppPools\$SiteName" -Name managedPipelineMode -Value 'Integrated'
Set-ItemProperty -Path "IIS:\AppPools\$SiteName" -Name startMode -Value 'AlwaysRunning'
Set-ItemProperty -Path "IIS:\AppPools\$SiteName" -Name processModel.idleTimeout -Value '00:00:00'
Write-Host "  App pool '$SiteName' created (.NET 4.0 Integrated)"

# Site
New-IISSite -Name $SiteName -PhysicalPath $SitePath -BindingInformation "*:$($Port):" -Force
Start-Sleep 1
Write-Host "  Site '$SiteName' created on port $Port"

Write-OK

# ---- 6: Configure Windows Authentication ----
Write-Step 6 $TotalSteps 'Configure Windows Authentication'

& $appcmd unlock config /section:windowsAuthentication /commit:APPHOST 2>$null
& $appcmd unlock config /section:anonymousAuthentication /commit:APPHOST 2>$null
& $appcmd set config "$SiteName" /section:windowsAuthentication /enabled:true /commit:APPHOST
& $appcmd set config "$SiteName" /section:anonymousAuthentication /enabled:false /commit:APPHOST

Write-OK

# ---- 7 (Update only): Restore data ----
if ($Mode -eq 'Update') {
    Write-Step 7 $TotalSteps 'Restore data'

    if (-not (Test-Path $DataDir)) {
        New-Item -Path $DataDir -ItemType Directory -Force | Out-Null
    }

    $surveyBackup = Join-Path $BackupDir 'survey.json'
    $configBackup = Join-Path $BackupDir 'config.json'

    if (Test-Path $surveyBackup) {
        Copy-Item $surveyBackup (Join-Path $DataDir 'survey.json') -Force
        Write-Host "  survey.json restored"
    } else {
        Write-Warn "survey.json not found in backup  --  starting with empty database"
        if (-not (Test-Path (Join-Path $DataDir 'survey.json'))) {
            '{"surveys":[],"questions":[],"options":[],"submissions":[],"answers":[],"admins":[]}' |
                Set-Content -Path (Join-Path $DataDir 'survey.json') -Encoding UTF8
        }
    }

    if (Test-Path $configBackup) {
        Copy-Item $configBackup $ConfigPath -Force
        Write-Host "  config.json restored"
    } else {
        Write-Warn "config.json not found in backup  --  using default"
        if (-not (Test-Path $ConfigPath)) {
            '{"initial_admin":""}' | Set-Content -Path $ConfigPath -Encoding ASCII
        }
    }

    Write-OK
} else {
    # Fresh: init empty data if absent
    if (-not (Test-Path $DataDir)) {
        New-Item -Path $DataDir -ItemType Directory -Force | Out-Null
        Write-Host "  data/ created"
    }
    $surveyJson = Join-Path $DataDir 'survey.json'
    if (-not (Test-Path $surveyJson)) {
        '{"surveys":[],"questions":[],"options":[],"submissions":[],"answers":[],"admins":[]}' |
            Set-Content -Path $surveyJson -Encoding UTF8
        Write-Host "  data/survey.json initialized (empty)"
    }
    if (-not (Test-Path $ConfigPath)) {
        '{"initial_admin":""}' | Set-Content -Path $ConfigPath -Encoding ASCII
        Write-Host "  config.json created  --  edit initial_admin to your domain username (lowercase)"
    }
}

# ---- Final: Verify ----
Write-Host ''
Write-Host '=== Verification ===' -ForegroundColor Cyan

Start-IISSite -Name $SiteName -ErrorAction SilentlyContinue
Start-Sleep 1

try {
    $health = Invoke-WebRequest -Uri "http://localhost:$Port/asp/api.ashx?path=health" `
        -UseBasicParsing -TimeoutSec 10
    Write-Host "  Health check: $($health.Content)" -ForegroundColor Green
} catch {
    Write-Warn "Health check failed: $($_.Exception.Message)"
    Write-Host "  Manual verify: curl http://localhost:$Port/asp/api.ashx?path=health"
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Green
Write-Host '  Deployment complete!' -ForegroundColor Green
Write-Host "  URL: http://localhost:$Port" -ForegroundColor Green
Write-Host '========================================' -ForegroundColor Green
Write-Host ''
Write-Host '  Next steps:'
Write-Host "  1. Edit $ConfigPath"
Write-Host '     Set initial_admin to your domain username (lowercase)'
Write-Host '  2. Run: iisreset'
Write-Host "  3. Open: http://localhost:$Port"
