@echo off
title Survey - Uninstall HttpListener Service
echo ============================================
echo   Survey HttpListener Server  --  Uninstall
echo ============================================
echo.
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Administrator privileges required.
    pause
    exit /b 1
)
echo Stopping service...
sc stop SurveySvc >nul 2>&1
sc delete SurveySvc >nul 2>&1
echo Removing URL ACL...
netsh http delete urlacl url=http://+:80/ >nul 2>&1
echo Closing firewall rule...
netsh advfirewall firewall delete rule name="Survey HTTP 80" >nul 2>&1
echo.
echo Done. SurveyServer.exe and data/ are kept; delete manually if needed.
pause
