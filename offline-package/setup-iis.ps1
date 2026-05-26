<# Survey IIS Reverse Proxy Setup Script. Run as Administrator. #>

$ErrorActionPreference = "Stop"
$siteName = "SurveyProxy"
$sitePath = "C:\inetpub\survey-proxy"

Write-Host "=== 1/5 Install IIS + Windows Auth ==="
Install-WindowsFeature -Name Web-Server, Web-Windows-Auth, Web-Mgmt-Console

Write-Host "=== 2/5 Create IIS Site ==="
New-Item -Path $sitePath -ItemType Directory -Force -ErrorAction SilentlyContinue
New-IISSite -Name $siteName -PhysicalPath $sitePath -BindingInformation "*:80:" -Force

# Use appcmd to avoid PowerShell IIS provider cache conflicts
Write-Host "  Disable Anonymous, Enable Windows Auth..."
& $env:SystemRoot\System32\inetsrv\appcmd.exe set config "$siteName" /section:anonymousAuthentication /enabled:false /commit:APPHOST
& $env:SystemRoot\System32\inetsrv\appcmd.exe set config "$siteName" /section:windowsAuthentication /enabled:true /commit:APPHOST

Write-Host "=== 3/5 Unlock rewrite sections and deploy web.config ==="
# Unlock allowedServerVariables and register HTTP_X_FORWARDED_USER globally
& $env:SystemRoot\System32\inetsrv\appcmd.exe unlock config /section:system.webServer/rewrite/allowedServerVariables 2>$null
& $env:SystemRoot\System32\inetsrv\appcmd.exe set config /section:system.webServer/rewrite/allowedServerVariables /+"[name='HTTP_X_FORWARDED_USER']" /commit:APPHOST
$webConfig = @'
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
        </rewrite>
    </system.webServer>
</configuration>
'@
# Write web.config as UTF-8 WITHOUT BOM (BOM before <?xml is invalid XML)
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText("$sitePath\web.config", $webConfig, $utf8NoBom)

Write-Host "=== 4/5 Enable ARR Proxy ==="
# proxy section is locked by default — must unlock at global level first
& $env:SystemRoot\System32\inetsrv\appcmd.exe unlock config /section:system.webServer/proxy 2>$null
& $env:SystemRoot\System32\inetsrv\appcmd.exe set config /section:system.webServer/proxy /enabled:true 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: ARR proxy not enabled. Install ARR module first:"
    Write-Host "  https://www.iis.net/downloads/microsoft/application-request-routing"
}

Write-Host "=== 5/5 Done ==="
Write-Host ""
Write-Host "IIS reverse proxy configured."
Write-Host "  URL:      http://<server-name>"
Write-Host "  Backend:  http://localhost:8080"
Write-Host ""
Write-Host "Prerequisites (install manually if missing):"
Write-Host "  URL Rewrite:  https://www.iis.net/downloads/microsoft/url-rewrite"
Write-Host "  ARR:          https://www.iis.net/downloads/microsoft/application-request-routing"
Write-Host ""
Write-Host "Then edit config.json: set mock_username to empty string"