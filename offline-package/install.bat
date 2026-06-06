@echo off
title Survey - Deploy

echo ============================================
echo   Survey System  --  Deploy
echo   Windows Server 2022 + IIS + ASP.NET 4.8
echo ============================================
echo.

:: ============================================================
:: 1. Admin check
:: ============================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Administrator privileges required.
    echo         Right-click install.bat ^> Run as administrator
    pause
    exit /b 1
)

:: ============================================================
:: 2. Detect existing Survey site
:: ============================================================
set "SITE_STATE=notfound"
set "OLD_PATH="
set "OLD_PORT=80"

for /f "tokens=1,2,3 delims=|" %%a in ('powershell -NoProfile -Command ^
  "try { $s=Get-IISSite -Name 'Survey' -ErrorAction Stop; $b=$s.Bindings[0].BindingInformation; $port=$b.Split(':')[1]; if(!$port){$port='80'}; Write-Host ('{0}|{1}|{2}' -f $s.State, $s.Applications['/'].VirtualDirectories['/'].PhysicalPath, $port) } catch { Write-Host 'notfound||80' }" 2^>nul') do (
    set "SITE_STATE=%%a"
    set "OLD_PATH=%%b"
    set "OLD_PORT=%%c"
)

if /i "%SITE_STATE%"=="notfound" goto :fresh_install

:: ============================================================
:: 3. Existing site  --  prompt user
:: ============================================================
echo Existing Survey site detected:
echo   State : %SITE_STATE%
echo   Path  : %OLD_PATH%
echo   Port  : %OLD_PORT%
echo.
echo Choose action:
echo   [U] Update  --  keep all survey data and config
echo   [R] Reinstall  --  DELETE everything, fresh start
echo   [C] Cancel  --  exit without changes
echo.

:ask_choice
set "USER_CHOICE="
set /p "USER_CHOICE=Enter U/R/C: "
if /i "%USER_CHOICE%"=="C" goto :cancel
if /i "%USER_CHOICE%"=="R" goto :reinstall
if /i "%USER_CHOICE%"=="U" goto :update
echo Invalid choice. Enter U, R, or C.
goto :ask_choice

:: ============================================================
:: UPDATE: backup data, then fresh setup, then restore
:: ============================================================
:update
echo.
echo ============================================
echo   UPDATE  --  Preserving data
echo ============================================

:: Backup data from old site path
set "BACKUP_DIR=%TEMP%\survey_backup_%date:~0,4%%date:~5,2%%date:~8,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
set "BACKUP_DIR=%BACKUP_DIR: =0%"
mkdir "%BACKUP_DIR%" 2>nul

set "HAS_DATA=0"
if exist "%OLD_PATH%\data\survey.json" (
    copy "%OLD_PATH%\data\survey.json" "%BACKUP_DIR%\survey.json" /Y >nul
    echo   [OK] survey.json backed up
    set "HAS_DATA=1"
) else (
    echo   [--] survey.json not found at old path
)

if exist "%OLD_PATH%\config.json" (
    copy "%OLD_PATH%\config.json" "%BACKUP_DIR%\config.json" /Y >nul
    echo   [OK] config.json backed up
) else (
    echo   [--] config.json not found at old path
)

echo   Backup saved to: %BACKUP_DIR%
echo.

:: Deploy with update mode
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "& { & '%~dp0setup-iis.ps1' -Mode Update -BackupDir '%BACKUP_DIR%' -Port %OLD_PORT% }"

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Deployment failed. Your data is safe at:
    echo         %BACKUP_DIR%
    pause
    exit /b 1
)
goto :done

:: ============================================================
:: REINSTALL: confirm then fresh
:: ============================================================
:reinstall
echo.
echo ============================================
echo   REINSTALL  --  All data will be DELETED!
echo ============================================
echo.
echo   Old path: %OLD_PATH%
echo   This will remove existing Survey site and all data.
echo.
set "CONFIRM="
set /p "CONFIRM=Type DELETE to confirm: "
if not "%CONFIRM%"=="DELETE" (
    echo Cancelled.
    pause
    exit /b 0
)

:: Optional: delete old data directory
if exist "%OLD_PATH%\data\survey.json" (
    echo   Deleting old survey data...
    del "%OLD_PATH%\data\survey.json" 2>nul
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "& { & '%~dp0setup-iis.ps1' -Mode Fresh -Port %OLD_PORT% }"

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Deployment failed.
    pause
    exit /b 1
)
goto :done

:: ============================================================
:: FRESH: check port 80, then install
:: ============================================================
:fresh_install
echo No existing Survey site found.
echo.

:: Check if another site occupies port 80
set "PORT80_SITE="
for /f "delims=" %%a in ('powershell -NoProfile -Command ^
  "try { $sites=Get-IISSite -ErrorAction Stop; foreach($s in $sites){ foreach($b in $s.Bindings){ if($b.BindingInformation -eq '*:80:'){ Write-Host $s.Name; exit } } } } catch { }" 2^>nul') do set "PORT80_SITE=%%a"

if not "%PORT80_SITE%"=="" (
    if /i "%PORT80_SITE%"=="Default Web Site" (
        echo Default Web Site occupies port 80.
        echo The installer will stop and remove it automatically.
        echo.
    ) else (
        echo [WARNING] Port 80 is occupied by: %PORT80_SITE%
        echo.
        echo The installer will attempt to resolve this. If it fails:
        echo   1. Stop or remove the conflicting site in IIS Manager
        echo   2. Run this installer again
        echo.
    )
)

echo Starting fresh install...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "& { & '%~dp0setup-iis.ps1' -Mode Fresh -Port 80 }"

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Deployment failed.
    pause
    exit /b 1
)
goto :done

:: ============================================================
:: Done
:: ============================================================
:done
echo.
echo ============================================
echo   All done. Verify:
echo     curl http://localhost/asp/api.ashx?path=health
echo ============================================
pause
exit /b 0

:cancel
echo.
echo Cancelled.
pause
exit /b 0
