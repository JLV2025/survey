@echo off
chcp 65001 >nul
title Survey System - Install

echo ========================================
echo   Internal Survey System - Install
echo   Windows Server 2022 + IIS + ASP.NET 4.8
echo ========================================
echo.

REM Check admin rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Please run as Administrator!
    echo         Right-click install.bat ^> "Run as administrator"
    pause
    exit /b 1
)

echo [1/4] Installing IIS + Windows Auth + ASP.NET 4.8...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Install-WindowsFeature -Name Web-Server, Web-Asp-Net45, Web-Net-Ext45, Web-ISAPI-Ext, Web-ISAPI-Filter, Web-Windows-Auth, Web-Default-Doc, Web-Static-Content, Web-Filtering, Web-Mgmt-Console"
if %errorlevel% neq 0 (
    echo [WARN] Some features may not have installed. Check: Get-WindowsFeature Web-Server, Web-Asp-Net45
)
echo   OK

echo [2/4] Registering ASP.NET 4.8 with IIS...
if exist "%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\aspnet_regiis.exe" (
    "%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\aspnet_regiis.exe" -i
    echo   ASP.NET 4.8 registered.
) else (
    echo   SKIP: aspnet_regiis.exe not found (not needed on Server 2016+)
)
echo   OK

echo [3/4] Configuring IIS site...
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { Import-Module WebAdministration; $s='Survey'; $p='%cd%'; $e=Get-IISSite -Name $s -ErrorAction SilentlyContinue; if($e){Remove-IISSite -Name $s -Confirm:$false;Start-Sleep 2}; $pp='IIS:\AppPools\'+$s; if(Test-Path $pp){Remove-Item $pp -Recurse -Force;Start-Sleep 1}; New-WebAppPool -Name $s -Force; Set-ItemProperty -Path ('IIS:\AppPools\'+$s) -Name managedRuntimeVersion -Value 'v4.0'; New-IISSite -Name $s -PhysicalPath $p -BindingInformation '*:80:' -Force; Start-Sleep 1; Write-Host '  Site created' }"
echo   OK

echo [4/4] Enabling Windows Authentication...
"%SystemRoot%\System32\inetsrv\appcmd.exe" unlock config /section:windowsAuthentication /commit:APPHOST >nul 2>&1
"%SystemRoot%\System32\inetsrv\appcmd.exe" unlock config /section:anonymousAuthentication /commit:APPHOST >nul 2>&1
"%SystemRoot%\System32\inetsrv\appcmd.exe" set config "Survey" /section:windowsAuthentication /enabled:true /commit:APPHOST
"%SystemRoot%\System32\inetsrv\appcmd.exe" set config "Survey" /section:anonymousAuthentication /enabled:false /commit:APPHOST
echo   OK

REM Create data directory
if not exist "data" mkdir data
if not exist "config.json" echo {"initial_admin": ""}> config.json

echo.
echo ========================================
echo  Install Complete!
echo  Visit: http://localhost
echo.
echo  Next steps:
echo  1. Edit config.json → set initial_admin
echo     to your domain username (lowercase)
echo  2. Run: iisreset
echo  3. Verify: curl http://localhost/asp/api.ashx?path=health
echo ========================================
pause
