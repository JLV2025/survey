@echo off
title Survey  --  Sync Package

echo ============================================
echo   Sync dev files to offline-package/
echo ============================================
echo.

set "ROOT=%~dp0"
set "PKG=%ROOT%offline-package"

:: Ensure target directories exist
if not exist "%PKG%" mkdir "%PKG%"
if not exist "%PKG%\http-server" mkdir "%PKG%\http-server"
if not exist "%PKG%\web\css" mkdir "%PKG%\web\css"
if not exist "%PKG%\web\js\components" mkdir "%PKG%\web\js\components"
if not exist "%PKG%\web\js\vendor" mkdir "%PKG%\web\js\vendor"
if not exist "%PKG%\data" mkdir "%PKG%\data"

echo [1/2] Syncing code files...

:: Backend server
copy /Y "%ROOT%http-server\SurveyServer.cs" "%PKG%\http-server\SurveyServer.cs" >nul
copy /Y "%ROOT%http-server\SurveyServer.exe.config" "%PKG%\http-server\SurveyServer.exe.config" >nul
copy /Y "%ROOT%http-server\README.md" "%PKG%\http-server\README.md" >nul
echo    http-server/*

:: Deploy scripts
copy /Y "%ROOT%install.bat" "%PKG%\install.bat" >nul
copy /Y "%ROOT%uninstall.bat" "%PKG%\uninstall.bat" >nul
echo    install.bat / uninstall.bat

:: Frontend assets
copy /Y "%ROOT%web\css\style.css" "%PKG%\web\css\style.css" >nul
echo    web/css/style.css

copy /Y "%ROOT%web\js\api.js" "%PKG%\web\js\api.js" >nul
copy /Y "%ROOT%web\js\app.js" "%PKG%\web\js\app.js" >nul
copy /Y "%ROOT%web\js\i18n.js" "%PKG%\web\js\i18n.js" >nul
echo    web/js/*.js

xcopy /Y /Q "%ROOT%web\js\components\*.js" "%PKG%\web\js\components\" >nul
echo    web/js/components/*.js

xcopy /Y /Q "%ROOT%web\js\vendor\*.js" "%PKG%\web\js\vendor\" >nul
echo    web/js/vendor/*.js

if exist "%ROOT%web\logo.gif" (
    copy /Y "%ROOT%web\logo.gif" "%PKG%\web\logo.gif" >nul
    echo    web/logo.gif
)

:: index.html -> package root (entry)
copy /Y "%ROOT%web\index.html" "%PKG%\index.html" >nul
echo    web/index.html ^=^> offline-package/index.html

echo.
echo [2/2] Skipping runtime data (preserve server copy)...
echo    ^^! data/survey.json   --  kept from server
echo    ^^! config.json        --  kept from server

echo.
echo ============================================
echo   Sync complete.
echo   Deploy: copy offline-package\ to server, run install.bat
echo ============================================
pause
