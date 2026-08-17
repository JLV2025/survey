# 更新方法 / Update Guide

系统为 HttpListener 独立服务（`SurveySvc`）。更新时**永远不要覆盖**
`data/survey.json` 和 `config.json`（数据库与管理员配置）。

---

## 一键更新（推荐）

1. 将新版 `offline-package/` 拷贝到服务器
2. 管理员运行 **`install.bat`**
   （脚本自动：停止旧服务 → 重新编译 `SurveyServer.exe` → 覆盖 → 启动服务，数据不丢失）

## 手动更新

```bat
sc stop SurveySvc

:: 覆盖前端
xcopy "新版本\web\*" "部署目录\web\" /E /Y
:: 覆盖后端（重新编译）
copy "新版本\SurveyServer.exe" "部署目录\SurveyServer.exe" /Y
:: 覆盖入口页（如需）
copy "新版本\index.html" "部署目录\index.html" /Y

:: 不要覆盖 data/survey.json 和 config.json

sc start SurveySvc
```

> 后端代码变更时需重新编译 `SurveyServer.cs`：
> ```bat
> "%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /codepage:65001 /r:System.ServiceProcess.dll /out:SurveyServer.exe http-server\SurveyServer.cs
> ```

## 变更对照表

| 变更内容 | 需更新文件 | 需重启服务 |
|---------|-----------|-----------|
| 前端页面 | `web/**/*` 全部覆盖 | 否（清浏览器缓存） |
| 后端 API | `SurveyServer.exe`（重编译后） | 是 |
| 监听端口 | `SurveyServer.exe.config` | 是 |

## 更新后验证

```bat
:: 健康检查
curl --ntlm -u : http://localhost/asp/api.ashx?path=health
:: 预期: {"ok":true,"data":"OK"}

:: 当前用户（验证认证）
curl --ntlm -u : http://localhost/asp/api.ashx?path=me
:: 预期: {"ok":true,"data":{"username":"你的域账号","is_admin":false}}

:: 认证诊断页（浏览器访问）
:: http://<服务器主机名>/asp/diag.ashx
```

## 数据备份

更新前务必备份：

```bat
:: 备份（注意：备份文件不要放在部署目录内）
copy "部署目录\data\survey.json" "C:\backup\survey_%date:~0,4%%date:~5,2%%date:~8,2%.json"
copy "部署目录\config.json" "C:\backup\config_%date:~0,4%%date:~5,2%%date:~8,2%.json"
```

恢复数据：

```bat
copy "C:\backup\survey_20260604.json" "部署目录\data\survey.json" /Y
sc restart SurveySvc
```

## 常见问题 / Troubleshooting

### 取不到用户账号（401 或空用户名）

**第一步：确认访问方式**（最常见原因）
- 必须用**主机名/域名**访问：`http://服务器主机名/`
- Chrome/Edge 对 **IP 地址**默认不发送域凭据 → 换主机名即可

**第二步：确认服务与认证**
```bat
sc query SurveySvc        :: 确认服务 Running
curl --ntlm -u : http://localhost/asp/diag.ashx   :: 查看身份注入
```
- 若 `Identity.Name` 为空 → 服务未启用集成认证，检查 `SurveyServer.exe`
  是否为最新编译版本（重新运行 `install.bat`）

### 管理员无法编辑问卷

- 确认 `config.json` 的 `initial_admin` 为**小写域账号**（不带域名前缀）
- 确认取到了账号（`/asp/diag.ashx` 显示用户名）
- 账号匹配成功后 `is_admin` 才为 true，管理按钮才会出现

### 80 端口被占用

```bat
:: 查看占用 80 端口的进程
netstat -ano | findstr ":80 "
:: 若是旧服务/旧站点，停止后重装：
sc stop SurveySvc
install.bat
```

或换端口：编辑 `SurveyServer.exe.config` 中 `listen` 值（如 `http://+:8080/`），重启服务。

### 服务启动失败

```bat
sc start SurveySvc
sc query SurveySvc
:: 查看系统事件日志：事件查看器 > Windows 日志 > 应用程序
```
常见原因：80 端口被占用（URL ACL 冲突）、缺少 .NET Framework 4.8。
重新运行 `install.bat` 会重建 URL ACL。

### 静态文件缓存

前端更新后若页面未变化，清除浏览器缓存，或将 `index.html` 中脚本版本号递增：

```html
<script src="/web/js/app.js?v=9"></script>
```
