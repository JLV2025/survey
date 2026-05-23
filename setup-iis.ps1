# Survey IIS 反向代理一键配置脚本
# 以管理员身份运行此脚本

$ErrorActionPreference = "Stop"
$siteName = "SurveyProxy"
$sitePath = "C:\inetpub\survey-proxy"

Write-Host "=== 1/5 安装 IIS + Windows 认证 ==="
Install-WindowsFeature -Name Web-Server, Web-Windows-Auth, Web-Mgmt-Console

Write-Host "=== 2/5 创建 IIS 站点 ==="
New-Item -Path $sitePath -ItemType Directory -Force -ErrorAction SilentlyContinue
New-IISSite -Name $siteName -PhysicalPath $sitePath -BindingInformation "*:80:" -Force

# 禁用匿名 / 启用 Windows 认证
Set-WebConfigurationProperty -Filter "system.webServer/security/authentication/anonymousAuthentication" -Name Enabled -Value False -Location $siteName
Set-WebConfigurationProperty -Filter "system.webServer/security/authentication/windowsAuthentication" -Name Enabled -Value True -Location $siteName

Write-Host "=== 3/5 写入反向代理规则 ==="
@'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <system.webServer>
        <rewrite>
            <rules>
                <rule name="ReverseProxy" stopProcessing="true">
                    <match url="(.*)" />
                    <action type="Rewrite" url="http://localhost:8080/{R:1}" />
                    <serverVariables>
                        <set name="HTTP_X-Forwarded-User" value="{REMOTE_USER}" />
                    </serverVariables>
                </rule>
            </rules>
            <allowedServerVariables>
                <add name="HTTP_X_FORWARDED_USER" />
            </allowedServerVariables>
        </rewrite>
    </system.webServer>
</configuration>
'@ | Out-File -FilePath "$sitePath\web.config" -Encoding UTF8

Write-Host "=== 4/5 启用 ARR 代理 ==="
Set-WebConfigurationProperty -Filter "system.webServer/proxy" -Name Enabled -Value True -Location $siteName

Write-Host "=== 5/5 完成 ==="
Write-Host ""
Write-Host "IIS 反向代理已配置完成！"
Write-Host "  访问地址: http://服务器名"
Write-Host "  Go 后端:  http://localhost:8080"
Write-Host ""
Write-Host "请确保已安装 URL Rewrite 和 ARR 模块:"
Write-Host "  https://www.iis.net/downloads/microsoft/url-rewrite"
Write-Host "  https://www.iis.net/downloads/microsoft/application-request-routing"
Write-Host ""
Write-Host "然后删除 config.json 中的 mock_username，改为:"
Write-Host '  "auth_mode": "ntlm"'
Write-Host '  "mock_username": ""'
