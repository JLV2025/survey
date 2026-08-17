@echo off
title Survey - Install Service (Windows Server)
echo ============================================
echo   Survey Server  --  Install
echo   Windows 集成认证，免登录取域账号，零外部依赖
echo ============================================
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Administrator privileges required.
    echo         Right-click this file ^> Run as administrator
    pause
    exit /b 1
)

set "ROOT=%~dp0"
set "CSC=%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe"

echo [1/5] Compiling SurveyServer.cs (offline, system csc.exe) ...
"%CSC%" /nologo /codepage:65001 /r:System.ServiceProcess.dll /out:"%ROOT%SurveyServer.exe" "%ROOT%http-server\SurveyServer.cs"
if errorlevel 1 (
    echo [ERROR] Compile failed.
    pause
    exit /b 1
)
echo    OK: SurveyServer.exe created
echo.

echo [2/5] Checking port 80 occupancy ...
powershell -NoProfile -Command ^
  "try { $c=Get-NetTCPConnection -LocalPort 80 -State Listen -ErrorAction Stop; Write-Host ('WARN: port 80 in use by PID ' + $c.OwningProcess) } catch { Write-Host 'OK: port 80 free' }"

echo.
echo [3/5] Registering URL ACL (http://+:80/) ...
netsh http add urlacl url=http://+:80/ user=Everyone
echo.

echo [4/5] Installing Windows service 'SurveySvc' ...
sc stop SurveySvc >nul 2>&1
sc delete SurveySvc >nul 2>&1
sc create SurveySvc binPath= ""%ROOT%SurveyServer.exe"" start= auto DisplayName= "Survey HttpListener Server"
if errorlevel 1 (
    echo [ERROR] sc create failed.
    pause
    exit /b 1
)
sc start SurveySvc
echo.

echo [5/5] Opening firewall port 80 ...
netsh advfirewall firewall delete rule name="Survey HTTP 80" >nul 2>&1
netsh advfirewall firewall add rule name="Survey HTTP 80" dir=in action=allow protocol=TCP localport=80
echo.

echo ============================================
echo   Install complete!
echo   Service : SurveySvc  (auto start)
echo   URL     : http://<server-hostname>/
echo   Verify  : http://<server-hostname>/asp/diag.ashx
echo   NOTE    : If port 80 is occupied, stop the process first:
echo             netstat -ano | findstr ":80 "  then stop it, re-run install.bat
echo ============================================
pause
