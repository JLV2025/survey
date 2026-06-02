<# Survey IIS Setup Script — Windows Auth + ASP. Run as Administrator. #>

$ErrorActionPreference = "Stop"
$siteName = "Survey"
$sitePath = (Get-Location).Path
$dataDir = Join-Path $sitePath "data"
$configPath = Join-Path $sitePath "config.json"

Write-Host "=== 1/5 Install IIS + Windows Auth + ASP ==="
Install-WindowsFeature -Name Web-Server, Web-Windows-Auth, Web-ASP, Web-Mgmt-Console

Write-Host "=== 2/5 Create IIS Site ==="
New-IISSite -Name $siteName -PhysicalPath $sitePath -BindingInformation "*:80:" -Force

# IIS Windows Auth ON, Anonymous OFF
# Edge/Chrome on domain machines auto-negotiate NTLM silently (no login prompt)
# because IIS handles auth at AuthenticateRequest stage, LOGON_USER 自动注入
Write-Host "  Enable Windows Auth, Disable Anonymous..."
& $env:SystemRoot\System32\inetsrv\appcmd.exe set config "$siteName" /section:windowsAuthentication /enabled:true /commit:APPHOST
& $env:SystemRoot\System32\inetsrv\appcmd.exe set config "$siteName" /section:anonymousAuthentication /enabled:false /commit:APPHOST

Write-Host "=== 3/5 Deploy web.config ==="
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$webConfig = @'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <system.webServer>
        <defaultDocument>
            <files>
                <clear />
                <add value="index.html" />
            </files>
        </defaultDocument>
        <rewrite>
            <rules>
                <rule name="ApiRewrite" stopProcessing="true">
                    <match url="^api/(.*)" />
                    <action type="Rewrite" url="/api.asp?__path={R:1}" />
                </rule>
            </rules>
        </rewrite>
        <security>
            <authentication>
                <windowsAuthentication enabled="true" />
                <anonymousAuthentication enabled="false" />
            </authentication>
            <requestFiltering>
                <denyUrlSequences>
                    <add sequence="data/" />
                    <add sequence="config.json" />
                </denyUrlSequences>
                <fileExtensions>
                    <add fileExtension=".json" allowed="false" />
                </fileExtensions>
            </requestFiltering>
        </security>
    </system.webServer>
</configuration>
'@
[System.IO.File]::WriteAllText("$sitePath\web.config", $webConfig, $utf8NoBom)

Write-Host "=== 4/5 Create data\ directory ==="
New-Item -Path $dataDir -ItemType Directory -Force -ErrorAction SilentlyContinue

Write-Host "=== 5/5 Write config.json (if not exists) ==="
if (-not (Test-Path $configPath)) {
    $initConfig = @'
{
  "initial_admin": ""
}
'@
    [System.IO.File]::WriteAllText($configPath, $initConfig, $utf8NoBom)
    Write-Host "  config.json created — fill in initial_admin with your domain username."
} else {
    Write-Host "  config.json already exists, skipping."
}

Write-Host ""
Write-Host "Done. IIS site 'Survey' configured."
Write-Host "  URL:      http://<server-name>"
Write-Host "  Path:     $sitePath"
Write-Host ""
Write-Host "Auth: IIS Windows Auth (Anonymous disabled)."
Write-Host "      ASP /api.asp receives LOGON_USER via Request.ServerVariables."
Write-Host "      Domain users authenticated silently (no login prompt)."
Write-Host ""
Write-Host "Prerequisites (install manually if missing):"
Write-Host "  URL Rewrite:  https://www.iis.net/downloads/microsoft/url-rewrite"
