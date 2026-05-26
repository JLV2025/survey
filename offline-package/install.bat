@echo off
chcp 65001 >nul

echo ============================================
echo   内部调查系统 - 离线安装
echo ============================================
echo.

echo 正在创建安装目录 C:\SurveyServer...
if not exist "C:\SurveyServer" mkdir "C:\SurveyServer"

echo 复制程序文件...
xcopy /E /I /Y "%~dp0web" "C:\SurveyServer\web" >nul
copy /Y "%~dp0survey.exe" "C:\SurveyServer\" >nul
copy /Y "%~dp0config.json" "C:\SurveyServer\" >nul
copy /Y "%~dp0setup-iis.ps1" "C:\SurveyServer\" >nul

echo 创建数据目录...
if not exist "C:\SurveyServer\data" mkdir "C:\SurveyServer\data"

echo.
echo 是否注册为 Windows 服务? (y/n)
set /p SVC_CHOICE=
if /i "%SVC_CHOICE%"=="y" (
    sc create "SurveyServer" binPath= "C:\SurveyServer\survey.exe" start= auto
    sc description "SurveyServer" "内部调查系统"
    sc start "SurveyServer"
    echo 服务已注册并启动。
) else (
    echo 跳过服务注册。请手动运行: C:\SurveyServer\survey.exe
)

echo.
echo ============================================
echo   安装完成！
echo.
echo   服务端口: 8080 (见 config.json)
echo   程序目录: C:\SurveyServer
echo   日志文件: C:\SurveyServer\survey.log
echo   数据文件: C:\SurveyServer\data\survey.json
echo.
echo   IIS 反向代理（可选，用于 NTLM 认证）:
echo     以管理员身份运行 PowerShell:
echo       Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
echo       C:\SurveyServer\setup-iis.ps1
echo   前提: 需安装 IIS URL Rewrite ^& ARR 模块
echo ============================================
pause
