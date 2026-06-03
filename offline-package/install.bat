@echo off
chcp 65001 >nul
title 调查系统 — 离线安装

echo ========================================
echo    内部调查系统 — 离线安装
echo ========================================
echo.

:: 检查是否管理员权限
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] 请以管理员身份运行此脚本！
    echo         右键点击 install.bat ^> "以管理员身份运行"
    pause
    exit /b 1
)

echo [1/4] 安装 IIS + Windows认证 + ASP.NET 4.8 功能...
dism /online /enable-feature /featurename:IIS-WebServerRole /all /quiet /norestart
dism /online /enable-feature /featurename:Web-Windows-Auth /all /quiet /norestart
dism /online /enable-feature /featurename:Web-ASP-Net45 /all /quiet /norestart
dism /online /enable-feature /featurename:Web-Mgmt-Console /all /quiet /norestart
echo   OK

echo [2/4] 注册 ASP.NET 4.8 到 IIS...
"%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\aspnet_regiis.exe" -i
echo   OK

echo [3/4] 配置 IIS 站点...
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { Import-Module WebAdministration; $s='Survey'; $p='%cd%'; $e=Get-IISSite -Name $s -ErrorAction SilentlyContinue; if($e){Remove-IISSite -Name $s -Confirm:$false;Start-Sleep 2}; $pp='IIS:\AppPools\'+$s; if(Test-Path $pp){Remove-Item $pp -Recurse -Force;Start-Sleep 1}; New-WebAppPool -Name $s -Force; New-IISSite -Name $s -PhysicalPath $p -BindingInformation '*:80:' -Force; Start-Sleep 1; Set-ItemProperty -Path $pp -Name managedRuntimeVersion -Value 'v4.0'; Write-Host 'Site created'}"
echo   OK

echo [4/4] 启用 Windows 认证...
"%SystemRoot%\System32\inetsrv\appcmd.exe" unlock config /section:windowsAuthentication /commit:APPHOST >nul 2>&1
"%SystemRoot%\System32\inetsrv\appcmd.exe" unlock config /section:anonymousAuthentication /commit:APPHOST >nul 2>&1
"%SystemRoot%\System32\inetsrv\appcmd.exe" set config "Survey" /section:windowsAuthentication /enabled:true /commit:APPHOST
"%SystemRoot%\System32\inetsrv\appcmd.exe" set config "Survey" /section:anonymousAuthentication /enabled:false /commit:APPHOST
echo   OK

:: 创建 data 目录
if not exist "data" mkdir data
if not exist "config.json" echo {"initial_admin": ""}> config.json

echo.
echo ========================================
echo  安装完成！
echo  访问: http://localhost
echo  修改 config.json 中的 initial_admin
echo  为你的域用户名，然后重启 IIS。
echo ========================================
pause