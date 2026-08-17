# 后端服务（HttpListener）

系统后端为 C# HttpListener 独立服务，Windows 集成认证（NTLM），
**免登录取域账号**，**零外部依赖**（.NET 4.8 自带，服务器无需联网，
编译用系统自带 csc.exe）。

## 原理

- 服务监听 HTTP 端口，启用 `IntegratedWindowsAuthentication`
- 浏览器访问时自动 401 协商，自动携带当前 Windows 域账号（无需输入密码）
- 后端从 `ctx.User.Identity.Name` 直接取 `DOMAIN\user`，去掉前缀得到用户名
- 只有域账号能访问；管理员名单来自 `config.json` 的 `initial_admin` 和
  `data/survey.json` 的 `admins[]`

## 目录布局（部署时）

`SurveyServer.exe` 必须与以下目录同级：

```
部署目录/
├── SurveyServer.exe          # 本服务（install.bat 自动编译）
├── SurveyServer.exe.config   # 监听配置（默认 http://+:80/）
├── index.html                # 前端入口
├── web/                      # 前端（Vue，原样复用）
├── data/survey.json          # 数据库
└── config.json               # 初始管理员
```

## 安装（Windows Server，管理员）

```bat
install.bat
```

脚本自动完成：
1. 用系统 csc.exe 离线编译 SurveyServer.cs
2. 注册 URL ACL（`http://+:80/`）
3. 创建并启动 Windows 服务 `SurveySvc`（开机自启）
4. 防火墙放行 80

> 若 80 端口被占用：先停止占用进程再安装（`netstat -ano | findstr ":80 "` 查看）

## 卸载

```bat
uninstall.bat
```

## 换端口

编辑 `SurveyServer.exe.config`：

```xml
<add key="listen" value="http://+:8080/" />
```

改完重启服务：`sc stop SurveySvc && sc start SurveySvc`

## 验证

```bat
:: 本机（应显示你的域账号）
curl --ntlm -u : http://localhost/asp/diag.ashx
:: 浏览器访问
http://<服务器主机名>/asp/diag.ashx
```

## 手动编译

```bat
"%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /codepage:65001 /r:System.ServiceProcess.dll /out:SurveyServer.exe http-server\SurveyServer.cs
```

## 代码结构

- `SurveyServer`：HttpListener 启动/停止、请求分发、静态文件服务
- `SurveyApi`：全部业务逻辑（存储、JSON、认证、路由、20 个 API、CSV 导出）
- `SurveyService` / `Program`：Windows 服务与前台模式入口

> 前台调试：直接运行 `SurveyServer.exe`（监听 `SurveyServer.exe.config` 配置的端口），
> 按 Enter 停止；作为服务运行时由 `install.bat` 注册。
