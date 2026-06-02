@echo off
chcp 65001 >nul

echo ============================================
echo   内部调查系统 - 安装
echo ============================================
echo.

echo 正在创建安装目录 C:\SurveyServer...
if not exist "C:\SurveyServer" mkdir "C:\SurveyServer"

echo 复制程序文件...
xcopy /E /I /Y "%~dp0web" "C:\SurveyServer\web" >nul
xcopy /E /I /Y "%~dp0asp" "C:\SurveyServer\asp" >nul
copy /Y "%~dp0config.json" "C:\SurveyServer\" >nul 2>nul
copy /Y "%~dp0web.config" "C:\SurveyServer\" >nul

echo 创建数据目录...
if not exist "C:\SurveyServer\data" mkdir "C:\SurveyServer\data"

echo.
echo 复制 IIS 配置脚本...
copy /Y "%~dp0setup-iis.ps1" "C:\SurveyServer\" >nul

echo.
echo ============================================
echo   安装完成！
echo.
echo   程序目录: C:\SurveyServer
echo                      ├── asp\api.asp     ^(REST API^)
echo                      ├── asp\json.asp    ^(JSON 工具^)
echo                      ├── web\            ^(前端页面^)
echo                      ├── data\           ^(survey.json 数据库^)
echo                      ├── config.json     ^(管理员配置^)
echo                      ├── web.config      ^(IIS URL 规则^)
echo                      └── setup-iis.ps1   ^(IIS 配置脚本^)
echo.
echo   下一步：以管理员身份运行 PowerShell:
echo     Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
echo     C:\SurveyServer\setup-iis.ps1
echo.
echo   前提: IIS 已安装 ^(含 URL Rewrite 模块^)。
echo   架构: IIS Windows Auth + Classic ASP，无需 Go 后端。
echo   域用户自动获取用户名，无登录弹窗。
echo ============================================
pause
