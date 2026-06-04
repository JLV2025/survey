@echo off
chcp 65001 >nul
title Survey System - Update

echo ========================================
echo   Survey System - Update
echo ========================================
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Run as Administrator
    pause
    exit /b 1
)

echo [1/3] Stopping web service...
net stop w3svc
echo   OK

echo [2/3] Copying files (preserving data)...
xcopy "web\*" "C:\inetpub\wwwroot\web\" /E /Y /Q
xcopy "asp\*" "C:\inetpub\wwwroot\asp\" /E /Y /Q
copy "web.config" "C:\inetpub\wwwroot\web.config" /Y >nul
copy "index.html" "C:\inetpub\wwwroot\index.html" /Y >nul
echo   OK

echo [3/3] Starting web service...
net start w3svc
echo   OK

echo.
echo ========================================
echo  Update Complete!
echo  Verify: curl http://localhost/asp/api.ashx?path=health
echo ========================================
pause
