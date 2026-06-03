# 内部调查系统 / Internal Survey System

轻量级企业调查系统，ASP.NET C# 后端 (IHttpHandler) + Vue 3 前端。
IIS 原生 Windows 集成认证，零编译部署，完全离线安装。

---

## 功能特点 / Features

- **问卷设计器**：创建/编辑/删除问卷，支持单选题、多选题、文本题
- **分步填写**：受访者以分步向导模式填写，每页一题
- **域认证**：IIS Windows Authentication，域用户自动识别，无登录弹窗
- **防重复提交**：基于用户名的提交锁定，已提交者不可重复填写
- **匿名调查**：匿名模式下不显示提交者信息，导出不含用户名列
- **实时统计**：ECharts 饼图 + 表格展示，提交后自动刷新
- **CSV 导出**：UTF-8 BOM 编码，Excel 直接打开
- **多语言**：简体中文 / English 界面切换
- **管理员白名单**：支持动态增删管理员 + config.json 初始管理员配置
- **级联删除**：删除问卷时自动清理关联的问题/选项/提交/回答

## 技术栈 / Tech Stack

| 层 Layer | 技术 Technology |
|---|---|
| 后端 Backend | ASP.NET C# 4.8 (IHttpHandler, 单文件 .ashx) |
| 前端 Frontend | Vue 3 + ECharts 5（本地 vendor，无 CDN） |
| 存储 Storage | JSON 文件（原子写入 + 文件锁） |
| 认证 Auth | IIS Windows Authentication |
| 导出 Export | CSV (UTF-8 BOM) |
| 部署 Deploy | 完全离线，零外部依赖 |

## 架构 / Architecture

```
survey/
├── asp/
│   └── api.ashx          # 后端 API (单文件 C# IHttpHandler)
├── web/
│   ├── index.html         # 前端入口
│   ├── logo.gif
│   ├── css/
│   │   └── style.css
│   └── js/
│       ├── api.js         # API 调用封装
│       ├── app.js         # Vue 3 路由 + 入口
│       ├── i18n.js        # 国际化
│       ├── components/    # Vue 组件
│       │   ├── survey-fill.js
│       │   ├── survey-stats.js
│       │   ├── admin-dashboard.js
│       │   ├── admin-survey-list.js
│       │   └── survey-designer.js
│       └── vendor/        # 本地 JS 库 (离线可用)
│           ├── vue.global.prod.js
│           └── echarts.min.js
├── data/
│   └── survey.json        # 数据库 (JSON 文件)
├── config.json            # 初始管理员配置
├── web.config             # IIS 配置
├── install.bat            # 一键安装脚本
├── setup-iis.ps1          # IIS 配置 PowerShell 脚本
└── offline-package/       # 离线部署包
```

## 安装部署 / Deployment

### 前提条件
- Windows Server 2016/2019/2022
- 已加入域（可选，仅使用域认证时需要）

### 一键安装（推荐）
1. 以 **管理员身份** 运行 `install.bat`
2. 修改 `config.json`，设置 `initial_admin` 为你的域用户名：
   ```json
   { "initial_admin": "your_domain_username" }
   ```
3. 重启 IIS：`iisreset`
4. 访问 `http://服务器IP`

### 手动安装
```batch
:: 1. 安装 IIS + Windows 认证 + ASP.NET 4.8
dism /online /enable-feature /featurename:IIS-WebServerRole /all /quiet
dism /online /enable-feature /featurename:Web-Windows-Auth /all /quiet
dism /online /enable-feature /featurename:Web-ASP-Net45 /all /quiet

:: 2. 注册 ASP.NET 4.8 到 IIS
"%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\aspnet_regiis.exe" -i

:: 3. 创建 IIS 站点
appcmd add apppool /name:"Survey" /managedRuntimeVersion:"v4.0"
appcmd add site /name:"Survey" /physicalPath:"C:\SurveyServer" /bindings:"http/*:80:"
appcmd set app "Survey/" /applicationPool:"Survey"

:: 4. 启用 Windows 认证
appcmd set config "Survey" /section:windowsAuthentication /enabled:true
appcmd set config "Survey" /section:anonymousAuthentication /enabled:false
```

### 验证安装
访问以下 URL 确认服务正常：
```
http://服务器IP/asp/api.ashx?path=health
```
预期返回：`{"ok":true,"data":"OK"}`

## 跨服务器迁移
1. 将项目目录完整复制到新服务器
2. 运行 `install.bat`
3. 复制 `data/survey.json` 和 `config.json`（保留原有数据）
4. 重启 IIS：`iisreset`

## API 文档 / API Reference

所有 API 通过单入口访问：
```
GET/POST/PUT/DELETE /asp/api.ashx?path=<route>
```

### 公开端点

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | health | 健康检查 |
| GET | me | 当前用户信息 |
| GET | check-admin | 检查管理员权限 |
| GET | surveys/{id} | 获取已发布问卷 |
| GET | surveys/{id}/check | 检查是否已提交 |
| POST | surveys/{id}/submit | 提交答卷 |
| GET | surveys/{id}/stats | 获取统计结果 |

### 管理端点 (需管理员权限)

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | admin | 管理员仪表盘 |
| GET | admin/surveys | 问卷列表 |
| POST | admin/surveys | 创建问卷 |
| PUT | admin/surveys/{id} | 更新问卷 |
| DELETE | admin/surveys/{id} | 删除问卷 |
| PUT | admin/surveys/{id}/status | 更新状态(draft/published/closed) |
| POST | admin/surveys/{id}/questions | 创建题目 |
| PUT | admin/surveys/{id}/questions/{qid} | 更新题目 |
| DELETE | admin/surveys/{id}/questions/{qid} | 删除题目 |
| PUT | admin/surveys/{id}/questions/reorder | 排序题目 |
| GET | admin/surveys/{id}/submissions | 提交记录 |
| GET | admin/surveys/{id}/export | CSV 导出 |
| GET | admin/users | 管理员列表 |
| POST | admin/users | 添加管理员 |
| DELETE | admin/users/{id} | 删除管理员 |

## 技术说明 / Notes

- 后端使用 `.ashx` (IHttpHandler) 而非 `.aspx`，避免行内代码 HTML 转义问题
- 所有 C# 代码兼容 **C# 5.0**（Windows Server 自带编译器版本）
- 零 NuGet 包依赖，纯 .NET Framework 4.8 内置 API
- JSON 序列化/反序列化手写实现，无第三方库
- 文件写入使用 tmp + rename 原子操作 + 文件锁，支持多用户并发
- 前端 Vue 3 + ECharts 已打包为单文件 vendor，无需 npm/yarn