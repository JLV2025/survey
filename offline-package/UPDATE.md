# 更新方法

## 快速更新（文件覆盖）

适用于已部署的服务器上更新代码。以管理员身份运行：

```bat
net stop w3svc
xcopy "新版本目录\*" "C:\inetpub\wwwroot\" /E /Y
net start w3svc
```

或者只覆盖变更文件：

| 变更内容 | 需更新文件 |
|---------|-----------|
| 前端页面 | `web/**/*` 全部覆盖 |
| 后端 API | `asp/api.ashx` |
| IIS 配置 | `web.config` |
| 管理员 | `config.json` |

更新后运行 `iisreset` 或 `net stop w3svc && net start w3svc` 生效。

## 保留数据更新

只替换代码文件，不覆盖数据目录：

```bat
xcopy "新版本\web\*" "C:\inetpub\wwwroot\web\" /E /Y
xcopy "新版本\asp\*" "C:\inetpub\wwwroot\asp\" /E /Y
copy "新版本\web.config" "C:\inetpub\wwwroot\web.config" /Y
:: 不要覆盖 data/survey.json
:: 不要覆盖 config.json
iisreset
```

## 更新后验证

```bat
curl http://localhost/asp/api.ashx?path=health
:: 预期: {"ok":true,"data":"OK"}

curl http://localhost/asp/api.ashx?path=me
:: 预期: {"ok":true,"data":{"username":"你的域账号",...}}
```

## 数据备份

更新前备份数据库和配置：

```bat
copy "C:\inetpub\wwwroot\data\survey.json" "C:\backup\survey_%date:~0,4%%date:~5,2%%date:~8,2%.json"
copy "C:\inetpub\wwwroot\config.json" "C:\backup\config_%date:~0,4%%date:~5,2%%date:~8,2%.json"
```

恢复数据：

```bat
copy "C:\backup\survey_20260604.json" "C:\inetpub\wwwroot\data\survey.json" /Y
```

## 常见问题

### 401 认证失败

检查 IIS 认证设置：

```bat
%SystemRoot%\System32\inetsrv\appcmd.exe list config "Survey" /section:windowsAuthentication
%SystemRoot%\System32\inetsrv\appcmd.exe list config "Survey" /section:anonymousAuthentication
```

正确配置：Windows Auth `enabled:true`，Anonymous Auth `enabled:false`。

### 删除操作不生效

确认 `web.config` 中 `<authorization>` 节点是 `<allow users="*" />` 而非 `<deny users="?" />`。

### 静态文件缓存

前端更新后若页面未变化，清除浏览器缓存，或将 `index.html` 中脚本引用版本号递增：

```html
<script src="/web/js/app.js?v=8"></script>
```

### IIS 不识别 .ashx

```bat
%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\aspnet_regiis.exe -i
iisreset
```

### 访问返回 404

检查站点物理路径和绑定：

```bat
%SystemRoot%\System32\inetsrv\appcmd.exe list site "Survey"
```

## 离线更新脚本

将以下保存为 `update.bat`，与新版本文件放在同一目录：

```bat
@echo off
chcp 65001 >nul
echo Survey System - Update

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Run as Administrator
    pause
    exit /b 1
)

echo [1/3] Stopping web service...
net stop w3svc

echo [2/3] Copying files (preserving data)...
xcopy "web\*" "C:\inetpub\wwwroot\web\" /E /Y /Q
xcopy "asp\*" "C:\inetpub\wwwroot\asp\" /E /Y /Q
copy "web.config" "C:\inetpub\wwwroot\web.config" /Y >nul

echo [3/3] Starting web service...
net start w3svc

echo Update complete.
echo Verify: curl http://localhost/asp/api.ashx?path=health
pause
```
