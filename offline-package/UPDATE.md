# 部署操作手册 / Operations Guide

系统为 HttpListener 独立服务（`SurveySvc`），Windows 集成认证，免登录取域账号。
**服务器无需联网**，所有文件离线部署。

---

## 目录结构 / Directory Structure

```
offline-package/                <- 部署根目录
├── http-server/                <- 后端源码
│   ├── SurveyServer.cs         <- 后端全部逻辑（单文件 C#，含认证/API/静态文件）
│   ├── SurveyServer.exe.config <- 监听配置（默认 http://+:80/）
│   └── README.md
├── web/                        <- 前端（Vue 3 + ECharts）
│   ├── css/style.css
│   └── js/...
├── index.html                  <- 前端入口
├── data/
│   └── survey.json             <- JSON 数据库
├── config.json                 <- 管理员配置（initial_admin）
├── install.bat                 <- 一键安装（编译 + 服务 + 防火墙）
├── uninstall.bat               <- 卸载
└── UPDATE.md                   <- 本手册
```

部署时 `SurveyServer.exe`（install.bat 自动编译）与 `web/`、`data/`、
`config.json`、`index.html` 同级。

---

## 部署 / Deployment

### 一键安装

1. 将 `offline-package/` 整个拷贝到服务器
2. 右键 **`install.bat`** → **以管理员身份运行**
3. 脚本自动完成：
   - 用系统自带 csc.exe **离线编译** `SurveyServer.exe`（服务器无需联网）
   - 注册 URL ACL（`http://+:80/`）
   - 创建并启动 Windows 服务 **`SurveySvc`**（开机自启）
   - 防火墙放行 80 端口
4. 若提示 80 端口被占用：先停止占用进程后重装（见常见问题）
5. 编辑 `config.json` 设置 `initial_admin`（小写域账号，可逗号分隔多个）
6. **用主机名访问**：`http://服务器主机名/`

### 换端口

编辑 `http-server/SurveyServer.exe.config`：

```xml
<add key="listen" value="http://+:8080/" />
```

复制到部署根目录后重启服务：`sc stop SurveySvc && sc start SurveySvc`

### 卸载

管理员运行 **`uninstall.bat`**（停止并删除服务、移除 URL ACL 与防火墙规则）。

---

## 更新 / Update

### 一键更新

将新版 `offline-package/` 拷贝到服务器，管理员运行 **`install.bat`**（数据不丢失）。

### 手动更新

```bat
sc stop SurveySvc
:: 覆盖前端与后端（保留 data/ 和 config.json）
xcopy "新版本\web\*" "部署目录\web\" /E /Y
copy "新版本\SurveyServer.exe" "部署目录\SurveyServer.exe" /Y
sc start SurveySvc
```

> 后端源码变更需重编译：
> ```bat
> "%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /codepage:65001 /r:System.ServiceProcess.dll /out:SurveyServer.exe http-server\SurveyServer.cs
> ```

### 单文件更新对照

| 变更 | 文件 | 需重启 |
|------|------|--------|
| 前端页面 | `web/js/components/*.js` | 否（清浏览器缓存） |
| 样式 | `web/css/style.css` | 否（清浏览器缓存） |
| 后端 API | `SurveyServer.exe` | `sc restart SurveySvc` |
| 监听配置 | `SurveyServer.exe.config` | `sc restart SurveySvc` |

> **更新时永远不要覆盖** `data/survey.json` 与 `config.json`。

---

## 验证 / Verification

```bat
:: 健康检查
curl --ntlm -u : http://localhost/asp/api.ashx?path=health
:: 预期: {"ok":true,"data":"OK"}

:: 当前用户（验证认证）
curl --ntlm -u : http://localhost/asp/api.ashx?path=me
:: 预期: {"ok":true,"data":{"username":"你的域账号","is_admin":...}}

:: 认证诊断页（浏览器）
:: http://<服务器主机名>/asp/diag.ashx
:: 预期显示 Identity.Name: [DOMAIN\账号]
```

---

## 数据备份 / Data Backup

### 备份

```bat
copy "部署目录\data\survey.json" "C:\backup\survey_%date:~0,4%%date:~5,2%%date:~8,2%.json"
copy "部署目录\config.json" "C:\backup\config_%date:~0,4%%date:~5,2%%date:~8,2%.json"
```

### 恢复

```bat
copy "C:\backup\survey_20260606.json" "部署目录\data\survey.json" /Y
sc restart SurveySvc
```

---

## 常见问题 / Troubleshooting

### 取不到用户账号（401 / 空用户名）

**① 访问方式（最常见）**：必须用**主机名/域名**访问（`http://服务器名/`），
**不要用 IP 地址**——Chrome/Edge 默认不向非 Intranet 区域发送域凭据。

**② 服务与认证**：
```bat
sc query SurveySvc
curl --ntlm -u : http://localhost/asp/diag.ashx
```
`Identity.Name` 为空 → 重新运行 `install.bat`（确保 exe 为最新编译）。

### 管理员无法编辑问卷

- `config.json` 的 `initial_admin` 必须是**小写域账号**（不带 `DOMAIN\` 前缀）
- 先用 `/asp/diag.ashx` 确认能取到账号，再检查 `is_admin`

### 80 端口被占用

```bat
netstat -ano | findstr ":80 "
:: 停止占用进程/旧服务后重装：
sc stop SurveySvc
install.bat
```
或改端口（见"换端口"）。

### 服务启动失败

```bat
sc query SurveySvc
:: 事件查看器 > Windows 日志 > 应用程序
```
常见原因：80 端口被占用、缺少 .NET Framework 4.8。重新运行 `install.bat` 重建。

### 前端不更新

清浏览器缓存，或递增 `index.html` 中脚本版本号：

```html
<script src="/web/js/app.js?v=9"></script>
```
