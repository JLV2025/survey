# 内部调查系统 / Internal Survey System

轻量级企业调查系统，Go 后端 + Vue 3 前端，单一 exe 部署，零外部依赖。

A lightweight enterprise survey system with Go backend and Vue 3 frontend. Single binary deployment, zero external dependencies.

---

## 中文文档

### 功能特性

- **问卷设计器**：拖拽式创建题目，支持单选、多选、填空题（单行/多行）
- **分步填写**：受访者以分步向导模式填写，每页一道题
- **身份识别**：支持 Windows NTLM 域认证；开发环境使用 Mock 模式
- **防重复提交**：基于用户名的提交锁定，已提交者不可重复填写
- **匿名调查**：匿名模式下不显示提交者信息，导出不含用户名列
- **实时统计**：ECharts 饼图 + 表格展示，30 秒自动刷新
- **Excel 导出**：导出原始数据（Sheet 1）和统计汇总（Sheet 2）
- **多语言**：简体中文 / English 界面切换
- **管理员白名单**：支持动态增删管理员

### 技术栈

| 层 | 技术 |
|---|---|
| 后端 | Go 1.24 + chi/v5 |
| 前端 | Vue 3 (CDN) + ECharts 5 |
| 存储 | JSON 文件存储 |
| 导出 | excelize/v2 |
| 部署 | 单一 exe，无外部依赖 |

### 快速开始

**前置条件**：Go 1.21+

```bash
git clone <repo-url>
cd survey
go build -o survey.exe .
./survey.exe
```

访问 `http://localhost:8080`，默认管理员账号 `admin`（Mock 模式下无需密码）。

### 部署到 Windows Server

#### 方式一：直接运行

```powershell
go build -o survey.exe .
Start-Process -NoNewWindow .\survey.exe
```

#### 方式二：注册为 Windows 服务（推荐）

使用 [NSSM](https://nssm.cc/)（Non-Sucking Service Manager）：

```powershell
nssm install SurveyService "C:\apps\survey\survey.exe"
nssm set SurveyService AppDirectory "C:\apps\survey"
nssm start SurveyService
```

#### 目录结构要求

```
survey/
├── survey.exe
├── config.json
├── web/              # 前端静态文件（必须）
│   ├── index.html
│   ├── css/
│   ├── js/
│   └── logo.gif
└── data/             # 数据目录（自动创建）
```

#### 防火墙配置

```powershell
New-NetFirewallRule -DisplayName "Survey System" -Direction Inbound -Port 8080 -Protocol TCP -Action Allow
```

### 配置说明

`config.json`：

| 字段 | 说明 |
|---|---|
| `port` | 服务端口 |
| `auth_mode` | 认证模式：`mock`（开发）或 `ntlm`（生产） |
| `mock_username` | Mock 模式下的固定用户名 |
| `initial_admin` | 首次启动时自动创建的管理员用户名 |
| `db_path` | JSON 数据文件路径 |

**NTLM 模式**：将 `auth_mode` 设为 `ntlm`，`mock_username` 留空。系统将从 `X-Forwarded-User` 或 `X-Remote-User` HTTP Header 读取用户名（由前置 NTLM 代理注入）。

### 使用指南

#### 管理员操作

1. 打开 `http://<服务器>:8080`，自动进入管理后台
2. **新建问卷**：点击"新建问卷"，填写标题、描述，选择是否匿名
3. **设计问卷**：点击"设计"，从左侧拖拽题型到画布，编辑题目和选项
4. **发布问卷**：在问卷列表点击"发布"
5. **分发链接**：点击"复制链接"，将 URL 发送给受访者
6. **查看统计**：点击"统计"，查看饼图和汇总数据
7. **导出数据**：点击"导出"，下载 Excel 文件

#### 受访者操作

1. 打开问卷链接（如 `http://<服务器>:8080/#/fill/<问卷ID>`）
2. 按分步向导逐题填写
3. 草稿自动保存在浏览器中，关闭后重新打开可恢复
4. 点击"提交"完成，不可修改
5. 提交后自动跳转至统计页面

### 项目结构

```
survey/
├── main.go                    # 入口
├── config.json                # 配置文件
├── internal/
│   ├── handler/               # HTTP 处理器
│   ├── middleware/auth.go     # 认证中间件
│   ├── model/models.go        # 数据模型
│   └── store/db.go            # JSON 文件存储
├── web/                       # 前端
│   ├── index.html             # SPA 入口
│   ├── css/style.css          # 样式
│   └── js/                    # Vue 组件 + API + i18n
└── data/                      # 运行时数据（自动创建）
```

---

## English Documentation

### Features

- Drag-and-drop survey designer (single/multiple choice, short/long text)
- Step wizard for respondents (one question per page)
- Windows NTLM domain auth; mock mode for development
- Duplicate submission prevention
- Anonymous survey mode
- Real-time ECharts statistics with 30s auto-refresh
- Excel export (raw data + summary)
- i18n: Simplified Chinese / English
- Admin whitelist management

### Tech Stack

| Layer | Technology |
|---|---|
| Backend | Go 1.24 + chi/v5 |
| Frontend | Vue 3 (CDN) + ECharts 5 |
| Storage | JSON file |
| Export | excelize/v2 |
| Deployment | Single binary, zero dependencies |

### Quick Start

**Prerequisites**: Go 1.21+

```bash
git clone <repo-url>
cd survey
go build -o survey.exe .
./survey.exe
```

Open `http://localhost:8080`. Default admin: `admin` (no password in mock mode).

### Deploy to Windows Server

#### Option 1: Direct Run

```powershell
go build -o survey.exe .
Start-Process -NoNewWindow .\survey.exe
```

#### Option 2: Windows Service (Recommended)

```powershell
nssm install SurveyService "C:\apps\survey\survey.exe"
nssm set SurveyService AppDirectory "C:\apps\survey"
nssm start SurveyService
```

#### Firewall

```powershell
New-NetFirewallRule -DisplayName "Survey System" -Direction Inbound -Port 8080 -Protocol TCP -Action Allow
```

### Configuration

`config.json`:

| Field | Description |
|---|---|
| `port` | Server port (default: 8080) |
| `auth_mode` | `mock` (dev) or `ntlm` (production) |
| `mock_username` | Fixed username in mock mode |
| `initial_admin` | Auto-created admin on first run |
| `db_path` | JSON data file path |

**NTLM Mode**: Set `auth_mode` to `ntlm`, leave `mock_username` empty. Username is read from `X-Forwarded-User` or `X-Remote-User` header.

### License

MIT
