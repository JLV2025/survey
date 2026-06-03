<#
.SYNOPSIS
  内部调查系统 — IIS 一键配置脚本
  以管理员身份运行。适用于 Windows Server 2022 + IIS + ASP.NET 4.8。
#>

$ErrorActionPreference = "Stop"
$siteName = "Survey"
$sitePath = (Get-Location).Path
$dataDir = Join-Path $sitePath "data"
$configPath = Join-Path $sitePath "config.json"

Write-Host "========================================"
Write-Host "  调查系统 IIS 部署脚本"
Write-Host "  目标: $siteName @ $sitePath"
Write-Host "========================================"

# ===== 1/5: 安装 IIS 功能 =====
Write-Host "`n=== 1/5: 安装 IIS + Windows Auth + ASP.NET 4.8 ==="
Install-WindowsFeature -Name Web-Server, Web-Asp-Net45, Web-Net-Ext45, Web-ISAPI-Ext, Web-ISAPI-Filter, Web-Windows-Auth, Web-Default-Doc, Web-Static-Content, Web-Filtering, Web-Mgmt-Console

# ===== 2/5: 注册 ASP.NET 4.8 到 IIS =====
Write-Host "`n=== 2/5: 注册 ASP.NET 4.8 ==="
$aspnetReg = "${env:SystemRoot}\Microsoft.NET\Framework64\v4.0.30319\aspnet_regiis.exe"
if (Test-Path $aspnetReg) {
    & $aspnetReg -i
    Write-Host "  ASP.NET 4.8 registered."
} else {
    Write-Host "  SKIP: aspnet_regiis.exe not found (not required on Server 2016+)"
}

# ===== 3/5: 创建/重置 IIS 站点 =====
Write-Host "`n=== 3/5: 创建 IIS 站点 ==="
# 删除旧站点和应用程序池
& ${env:SystemRoot}\System32\inetsrv\appcmd.exe delete site $siteName 2>$null
& ${env:SystemRoot}\System32\inetsrv\appcmd.exe delete apppool $siteName 2>$null
Start-Sleep 2

# 新建应用程序池 (.NET 4.0, Integrated)
& ${env:SystemRoot}\System32\inetsrv\appcmd.exe add apppool /name:$siteName /managedRuntimeVersion:"v4.0" /managedPipelineMode:"Integrated"
Start-Sleep 1

# 新建站点
& ${env:SystemRoot}\System32\inetsrv\appcmd.exe add site /name:$siteName /physicalPath:$sitePath /bindings:"http/*:80:"
Start-Sleep 1

# 将站点绑定到应用程序池
& ${env:SystemRoot}\System32\inetsrv\appcmd.exe set app "$siteName/" /applicationPool:$siteName

# ===== 4/5: 配置 Windows 认证 =====
Write-Host "`n=== 4/5: 配置 Windows 认证 ==="
# 解锁认证配置节（如果被锁定）
& ${env:SystemRoot}\System32\inetsrv\appcmd.exe unlock config /section:windowsAuthentication /commit:APPHOST 2>$null
& ${env:SystemRoot}\System32\inetsrv\appcmd.exe unlock config /section:anonymousAuthentication /commit:APPHOST 2>$null

# 启用 Windows 认证，禁用匿名认证
& ${env:SystemRoot}\System32\inetsrv\appcmd.exe set config $siteName /section:windowsAuthentication /enabled:true /commit:APPHOST
& ${env:SystemRoot}\System32\inetsrv\appcmd.exe set config $siteName /section:anonymousAuthentication /enabled:false /commit:APPHOST

# ===== 5/5: 创建 data 目录 + config.json =====
Write-Host "`n=== 5/5: 初始化数据目录 ==="
New-Item -Path $dataDir -ItemType Directory -Force -ErrorAction SilentlyContinue
Write-Host "  data/ created."

if (-not (Test-Path $configPath)) {
    $initConfig = '{"initial_admin": ""}'
    [System.IO.File]::WriteAllText($configPath, $initConfig, $utf8NoBom)
    Write-Host "  config.json created — edit initial_admin with your domain username."
} else {
    Write-Host "  config.json already exists, skipping."
}

# 启动站点
& ${env:SystemRoot}\System32\inetsrv\appcmd.exe start site $siteName 2>$null

Write-Host "`n========================================"
Write-Host "  部署完成!"
Write-Host "  URL:      http://localhost"
Write-Host "  站点路径: $sitePath"
Write-Host "  认证:     Windows 集成认证 (域用户自动登录)"
Write-Host "========================================"