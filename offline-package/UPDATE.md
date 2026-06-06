# Operations Guide

## Directory Structure

Deployed IIS site layout:

```
{site_root}\                 <- IIS site physical path
├── index.html               <- IIS default document, SPA entry
├── web.config               <- IIS config (Windows Auth, request filter, .ashx handler)
├── config.json              <- Admin config (initial_admin)
├── data/
│   └── survey.json          <- JSON database (surveys, questions, answers)
├── asp/
│   └── api.ashx             <- Backend API (ASP.NET C# IHttpHandler)
└── web/
    ├── css/style.css
    ├── js/
    │   ├── api.js           <- API client
    │   ├── app.js           <- Vue app + router
    │   ├── i18n.js          <- i18n (zh/en)
    │   ├── components/      <- Vue components
    │   └── vendor/          <- Third-party libs (Vue 3 + ECharts)
    └── logo.gif
```

## Deployment

### One-Click Deploy

1. Copy `offline-package/` to the server
2. Right-click `install.bat` → **Run as administrator**
3. The script auto-detects existing installation and prompts:
   - **Fresh install** — if no Survey site exists
   - **[U] Update** — if Survey site exists, keep all data
   - **[R] Reinstall** — if Survey site exists, DELETE all data
   - **[C] Cancel** — exit without changes
4. Edit `config.json` → set `initial_admin` to your domain username (lowercase)
5. Verify: `curl http://localhost/asp/api.ashx?path=health`

### Smart Detection Logic

```
install.bat
├── Admin check
├── Detect: Survey site in IIS?
│   ├── NO  → Fresh install
│   │         ├── Check port 80 conflicts
│   │         │   ├── Free → proceed
│   │         │   ├── Default Web Site → auto-remove
│   │         │   └── Other site → warn
│   │         └── setup-iis.ps1 -Mode Fresh
│   └── YES → Show state, path, port → Prompt [U/R/C]
│              ├── Update:
│              │   ├── Backup old-path/data/survey.json
│              │   ├── Backup old-path/config.json
│              │   ├── setup-iis.ps1 -Mode Update -BackupDir ...
│              │   └── Auto-restore data
│              ├── Reinstall:
│              │   ├── User confirms "DELETE"
│              │   ├── Delete old data
│              │   └── setup-iis.ps1 -Mode Fresh
│              └── Cancel → exit
```

### Custom Port

```powershell
.\setup-iis.ps1 -Mode Fresh -Port 8080
```

### What setup-iis.ps1 Does

1. Install IIS + Windows Auth + ASP.NET 4.8 features (idempotent)
2. Resolve port conflicts (auto-remove Default Web Site if needed)
3. Remove old Survey site + app pool
4. Clean ASP.NET temporary cache
5. Create app pool (.NET 4.0, Integrated, AlwaysRunning, no idle timeout)
6. Create IIS site
7. Configure Windows Authentication (enabled), Anonymous (disabled)
8. Initialize fresh data OR restore from backup (Update mode)
9. Health check

## Update

### Automated (Recommended)

Copy new `offline-package/` to server, run `install.bat` as admin, choose **[U] Update**.

The script:
1. Reads old site path from IIS
2. Backs up `survey.json` + `config.json` to `%TEMP%`
3. Deletes old site + app pool
4. Cleans ASP.NET temp cache
5. Creates fresh site + pool
6. Restores data from backup
7. Runs health check

Data is NEVER overwritten during update — the script backs up before any destructive action.

### Manual

```bat
iisreset /stop
xcopy "new\web\*" "{site_path}\web\" /E /Y
xcopy "new\asp\*" "{site_path}\asp\" /E /Y
copy "new\web.config" "{site_path}\web.config" /Y
copy "new\index.html" "{site_path}\index.html" /Y
iisreset /start
```

### Single File Update

| Change | Files | IIS Restart |
|--------|-------|-------------|
| Frontend pages | `web/js/components/*.js` | No (clear browser cache) |
| Styles | `web/css/style.css` | No (clear browser cache) |
| Backend API | `asp/api.ashx` | Yes (`iisreset`) |
| IIS config | `web.config` | Yes (`iisreset`) |

## Verification

```bat
:: Health check
curl http://localhost/asp/api.ashx?path=health
:: Expected: {"ok":true,"data":"OK"}

:: Current user (verify Windows Auth)
curl http://localhost/asp/api.ashx?path=me
:: Expected: {"ok":true,"data":{"username":"DOMAIN\\user","is_admin":false}}

:: Admin (after editing config.json)
curl http://localhost/asp/api.ashx?path=me
:: Expected: "is_admin":true
```

## Data Backup

### Manual Backup

```bat
set "DATE=%date:~0,4%%date:~5,2%%date:~8,2%"
copy "{site_path}\data\survey.json" "C:\backup\survey_%DATE%.json"
copy "{site_path}\config.json" "C:\backup\config_%DATE%.json"
```

### Restore

```bat
copy "C:\backup\survey_20260606.json" "{site_path}\data\survey.json" /Y
iisreset
```

## Troubleshooting

### 401 Authentication Failure

Check Windows Auth:

```bat
%SystemRoot%\System32\inetsrv\appcmd.exe list config "Survey" /section:windowsAuthentication
%SystemRoot%\System32\inetsrv\appcmd.exe list config "Survey" /section:anonymousAuthentication
```

Correct: Windows Auth `enabled:true`, Anonymous `enabled:false`.

If locked:
```bat
%SystemRoot%\System32\inetsrv\appcmd.exe unlock config /section:windowsAuthentication
%SystemRoot%\System32\inetsrv\appcmd.exe set config "Survey" /section:windowsAuthentication /enabled:true
```

### DELETE Returns 405

`web.config` must remove WebDAV:
```xml
<modules>
  <remove name="WebDAVModule" />
</modules>
<handlers>
  <remove name="WebDAV" />
</handlers>
```
Current `web.config` already includes this.

### Stale Browser Cache

Increment script version in `index.html`:
```html
<script src="/web/js/app.js?v=9"></script>
```

### IIS Doesn't Recognize .ashx

```bat
%SystemRoot%\System32\inetsrv\appcmd.exe list config "Survey" /section:handlers
```
If handler missing (rare on Server 2016+):
```bat
%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\aspnet_regiis.exe -i
iisreset
```

### Site Returns 404

```bat
%SystemRoot%\System32\inetsrv\appcmd.exe list site "Survey"
%SystemRoot%\System32\inetsrv\appcmd.exe list apppool "Survey"
```

### Slow First Request After Idle

`setup-iis.ps1` sets `startMode: AlwaysRunning` + `idleTimeout: 0`. If still slow:
```powershell
Import-Module WebAdministration
Set-ItemProperty -Path "IIS:\AppPools\Survey" -Name startMode -Value "AlwaysRunning"
```
