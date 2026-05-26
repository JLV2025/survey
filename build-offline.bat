@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ============================================
echo   内部调查系统 - 离线安装包构建
echo ============================================
echo.

set "OUT_DIR=offline-package"
set "PACKAGE_NAME=survey-offline"

REM 清理旧输出
if exist "%OUT_DIR%" rd /s /q "%OUT_DIR%"
mkdir "%OUT_DIR%"

echo [1/4] 编译 Go 二进制...
set CGO_ENABLED=0
set GOOS=windows
set GOARCH=amd64
go build -ldflags="-s -w" -o "%OUT_DIR%\survey.exe" .
if %ERRORLEVEL% neq 0 (
    echo 编译失败！
    exit /b 1
)
echo        survey.exe 编译完成

echo [2/4] 复制 Web 静态文件...
xcopy /E /I /Y "web" "%OUT_DIR%\web" >nul
echo        web\ 复制完成

echo [3/4] 复制配置和脚本...
copy /Y "config.prod.json" "%OUT_DIR%\config.json" >nul
copy /Y "setup-iis.ps1" "%OUT_DIR%" >nul
echo        config.json (from config.prod.json^)
echo        setup-iis.ps1

echo [4/4] 生成安装脚本 install.bat ...

(
echo @echo off
echo chcp 65001 ^>nul
echo.
echo echo ============================================
echo echo   内部调查系统 - 离线安装
echo echo ============================================
echo echo.
echo.
echo echo 正在创建安装目录 C:\SurveyServer...
echo if not exist "C:\SurveyServer" mkdir "C:\SurveyServer"
echo.
echo echo 复制程序文件...
echo xcopy /E /I /Y "%%~dp0web" "C:\SurveyServer\web" ^>nul
echo copy /Y "%%~dp0survey.exe" "C:\SurveyServer\" ^>nul
echo copy /Y "%%~dp0config.json" "C:\SurveyServer\" ^>nul
echo copy /Y "%%~dp0setup-iis.ps1" "C:\SurveyServer\" ^>nul
echo.
echo echo 创建数据目录...
echo if not exist "C:\SurveyServer\data" mkdir "C:\SurveyServer\data"
echo.
echo REM 创建 Windows 服务（可选，需要 sc.exe）
echo echo.
echo echo 是否注册为 Windows 服务？(y/n^)
echo set /p SVC_CHOICE=
echo if /i "%%SVC_CHOICE%%"=="y" (
echo     sc create "SurveyServer" binPath= "C:\SurveyServer\survey.exe" start= auto
echo     sc description "SurveyServer" "内部调查系统"
echo     sc start "SurveyServer"
echo     echo 服务已注册并启动。
echo ) else (
echo     echo 请手动运行: C:\SurveyServer\survey.exe
echo )
echo.
echo echo.
echo echo ============================================
echo echo   安装完成！
echo echo.
echo echo   服务端口: 8080 (见 config.json^)
echo echo   程序目录: C:\SurveyServer
echo echo   日志文件: C:\SurveyServer\survey.log
echo echo   数据文件: C:\SurveyServer\data\survey.json
echo echo.
echo echo   IIS 反向代理（可选，用于 NTLM 认证）:
echo echo     以管理员身份运行 PowerShell:
echo echo       Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
echo echo       C:\SurveyServer\setup-iis.ps1
echo echo   前提: 需安装 IIS URL Rewrite ^& ARR 模块
echo echo ============================================
echo pause
) > "%OUT_DIR%\install.bat"

echo        install.bat

echo.
echo ============================================
echo   构建完成！
echo   输出目录: %OUT_DIR%\
echo ============================================
dir /s /b "%OUT_DIR%"
echo.
echo 将 %OUT_DIR% 整个目录复制到服务器后，以管理员身份运行 install.bat 即可。
echo.
echo 注意: 若需要 IIS 反向代理，还需提前准备以下离线安装包:
echo   - URL Rewrite Module: https://www.iis.net/downloads/microsoft/url-rewrite
echo   - ARR 3.0: https://www.iis.net/downloads/microsoft/application-request-routing
pause
