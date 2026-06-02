# 内部调查系统 / Internal Survey System

轻量级企业调查系统，Classic ASP 后端 + Vue 3 前端，IIS 原生 Windows 认证，零编译部署。

A lightweight enterprise survey system with Classic ASP backend and Vue 3 frontend. IIS Native Windows Auth, zero-compile deployment.

---

## 功能特性 / Features

- **问卷设计器**：拖拽式创建题目，支持单选、多选、填空题（单行/多行）
- **分步填写**：受访者以分步向导模式填写，每页一道题
- **域认证**：IIS Windows Authentication，域用户自动识别，无登录弹窗
- **防重复提交**：基于用户名的提交锁定，已提交者不可重复填写
- **匿名调查**：匿名模式下不显示提交者信息，导出不含用户名列
- **实时统计**：ECharts 饼图 + 表格展示，30 秒自动刷新
- **CSV 导出**：UTF-8 BOM 编码，Excel 直接打开
- **多语言**：简体中文 / English 界面切换
- **管理员白名单**：支持动态增删管理员

## 技术栈 / Tech Stack

| 层 Layer | 技术 Technology |
|---|---|
| 后端 Backend | Classic ASP (VBScript) |
| 前端 Frontend | Vue 3 + ECharts 5（本地 vendor） |
| 存储 Storage | JSON 文件 |
| 认证 Auth | IIS Windows Authentication |
| 导出 Export | CSV (UTF-8 BOM) |
| 部署 Deploy | 纯脚本，零编译，零运行时依赖 |

## 架构 / Architecture

```
浏览器 Browser ──→ IIS (Windows Auth) ──→ api.asp ──→ data/survey.json
                  └──→ web/ (静态文件)
```

不再有 Go exe、不再有 localhost:8080 代理、不再有 ARR 模块。

## 快速开始 / Quick Start

**前置条件**：Windows Server 2016+，IIS + URL Rewrite 模块

```cmd
git clone https://github.com/JLV2025/survey.git
cd survey\offline-package
install.bat
```

以管理员身份运行 PowerShell：
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
C:\SurveyServer\setup-iis.ps1
```

在 `C:\SurveyServer\config.json` 中填入管理员域账号：
```json
{
  "initial_admin": "your_account"
}
```

访问 `http://<server-name>`。

## 部署 / Deploy

### 部署目录结构

```
C:\SurveyServer\
├── asp\
│   ├── api.asp              ← REST API (约 1100 行)
│   └── json.asp             ← JSON 编解码
├── web\                     ← 前端静态文件
│   ├── index.html
│   ├── logo.gif
│   ├── css\style.css
│   └── js\
│       ├── api.js
│       ├── app.js
│       ├── i18n.js
│       ├── vendor\
│       └── components\
├── data\
│   └── survey.json          ← 数据库（JSON 文件）
├── config.json              ← 管理员配置
├── web.config               ← IIS URL Rewrite 规则
├── setup-iis.ps1            ← IIS 一键配置脚本
└── install.bat              ← 安装脚本
```

### 安装步骤

1. 复制 `offline-package\` 到服务器 `C:\SurveyServer\`
2. 以管理员身份运行 `C:\SurveyServer\setup-iis.ps1`
3. 编辑 `C:\SurveyServer\config.json`，填入 `initial_admin`（域用户名）
4. 浏览器访问 `http://<server-name>`

### 一键配置脚本

`setup-iis.ps1` 自动完成：
- 安装 IIS + Windows 认证 + ASP 功能
- 创建 IIS 站点 "Survey"，绑定 80 端口
- 启用 Windows 认证，禁用匿名认证
- 部署 web.config（API 路由 + .json 访问拦截）
- 创建 data\ 目录和 config.json
- 安全加固：禁止 .json 文件直接 HTTP 访问

## 配置 / Configuration

`config.json`：

| 字段 | 说明 |
|---|---|
| `initial_admin` | 初始管理员域用户名（逗号分隔多个），首次启动后可为空 |

```json
{
  "initial_admin": "CORP\\your_account,jingl"
}
```

## API 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/me` | 当前用户信息（含 is_admin） |
| GET | `/api/check-admin` | 检查是否管理员 |
| GET | `/api/surveys/{id}` | 获取问卷（含题目） |
| GET | `/api/surveys/{id}/check` | 检查是否已提交 |
| POST | `/api/surveys/{id}/submit` | 提交问卷 |
| GET | `/api/surveys/{id}/stats` | 统计结果 |
| GET | `/api/admin/surveys` | 管理员：问卷列表 |
| POST | `/api/admin/surveys` | 创建问卷 |
| PUT | `/api/admin/surveys/{id}` | 更新问卷 |
| DELETE | `/api/admin/surveys/{id}` | 删除问卷 |
| PUT | `/api/admin/surveys/{id}/status` | 发布/关闭问卷 |
| POST | `/api/admin/surveys/{id}/questions` | 创建题目 |
| PUT | `/api/admin/surveys/{id}/questions/{qid}` | 更新题目 |
| DELETE | `/api/admin/surveys/{id}/questions/{qid}` | 删除题目 |
| PUT | `/api/admin/surveys/{id}/questions/reorder` | 题目排序 |
| GET | `/api/admin/surveys/{id}/submissions` | 提交记录 |
| GET | `/api/admin/surveys/{id}/export` | 导出 CSV |
| GET | `/api/admin/users` | 管理员列表 |
| POST | `/api/admin/users` | 添加管理员 |
| DELETE | `/api/admin/users/{id}` | 删除管理员 |

## 项目结构 / Project Structure

```
survey/
├── asp/                       ← Classic ASP 后端
│   ├── api.asp                ← 主 API（路由 + 全部 handler）
│   └── json.asp               ← JSON 编解码（纯 VBScript）
├── web/                       ← 前端（Vue 3 SPA）
│   ├── index.html
│   ├── logo.gif
│   ├── css/style.css
│   └── js/
│       ├── api.js             ← API 封装
│       ├── app.js             ← 路由 + 初始化
│       ├── i18n.js            ← 中英文翻译
│       ├── vendor/            ← 本地化 JS 库
│       └── components/        ← Vue 组件
├── config.json                ← 管理员配置
├── web.config                 ← IIS URL Rewrite 规则
├── setup-iis.ps1              ← IIS 一键配置脚本
├── offline-package/           ← 部署包（复制即用）
│   ├── asp/
│   ├── web/
│   ├── data/
│   ├── config.json
│   ├── web.config
│   ├── setup-iis.ps1
│   └── install.bat
├── _go-backend/               ← (归档) Go 后端源码 + internal/
├── _vendor/                   ← IIS 模块安装包 (rewrite/ARR)
└── data/                      ← 运行时数据（自动创建）
```

## 开发说明 / Development

### 后端

- 一个 `api.asp`（~1100 行 VBScript）处理全部 REST API
- URL 路由通过 IIS rewrite 规则：`/api/*` → `/api.asp?__path=*`
- JSON 编解码为纯 VBScript 手动实现（`json.asp`），无需 COM 组件
- Windows 认证由 IIS 层面处理，ASP 通过 `LOGON_USER` 获取用户名
- 数据存储在 `data/survey.json`，`Application.Lock` 保证并发安全

### 前端

- Vue 3 CDN 模式，无需 Node.js 构建环境
- 直接修改 `web/js/` 中的文件即可生效
- 静态资源走 `/static/` 路径（web.config rewrite → web/）

### 功能亮点

- **管理员按钮**：admin-dashboard 标题栏直接显示，无需经过"新建问卷"
- **填写入口**：每个问卷卡有"填写"按钮，直接跳转填写页
- **空题目提示**：问卷无题目时显示 📋 提示，不再只有灰色按钮
- **错误区分**：网络故障显示"服务器错误"，业务错误显示具体原因
- **CSV 导出**：UTF-8 BOM，Excel 双击打开不乱码

### 安全措施

- `.json` 文件禁止 HTTP 直接访问（IIS request filtering）
- 管理员路由统一 `RequireAdmin()` 守卫
- CSV 导出文件名过滤控制字符
- JSON 解析器深度限制

## 故障排查 / Troubleshooting

| 现象 | 原因 | 解决 |
|---|---|---|
| 页面空白，无导航栏 | `/api/me` 未返回用户信息 | 检查 IIS Windows 认证是否启用；匿名认证是否禁用 |
| "认证失败" | LOGON_USER 为空 | 确保浏览器使用 FQDN 访问（非 IP），站点在 Intranet Zone |
| "无管理员权限" | 用户名不在管理员列表 | 检查 `config.json` 的 `initial_admin`，或通过 `/api/admin/users` 添加 |
| 问卷填写页显示"暂无题目" | 问卷已发布但未添加题目 | 在设计器中添加题目后重新发布 |
| 数据修改后重启丢失 | `data/` 目录无写入权限 | 给 IIS 应用池账户（IIS APPPOOL\Survey）添加 `data/` 写入权限 |
| CSV 导出乱码 | Excel 未正确识别编码 | 确认用 Excel（非记事本）打开；CSV 带有 UTF-8 BOM 头 |

## License

MIT
