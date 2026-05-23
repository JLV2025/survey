# OpenWolf

@.wolf/OPENWOLF.md

This project uses OpenWolf for context management. Read and follow .wolf/OPENWOLF.md every session. Check .wolf/cerebrum.md before generating code. Check .wolf/anatomy.md before reading files.


# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

内部调查系统 - 轻量级调查平台，部署于 Windows Server 2022。
- 后端：Go (Golang) - 编译为单一 exe，无需运行时依赖
- 前端：Vue.js (CDN) + ECharts - 无需 Node 构建环境
- 数据库：SQLite - 零配置、单文件
- 端口：8080

## 技术栈

### 后端 (Go)
- 标准库优先
- 关键依赖：
  - github.com/mattn/go-sqlite3 - SQLite 驱动
  - github.com/golang-jwt/jwt/v5 - JWT 认证
  - github.com/go-ntlmclient/ntlmclient - NTLM 域认证
  - gopkg.in/yaml.v3 - YAML 配置解析

### 前端 (Vue 3 + CDN)
- Vue.js 3.x (CDN 引入，无构建)
- ECharts 图表库
- Tailwind CSS (可选，用于样式)

## 目录结构

```
survey/
├── backend/                  # Go 后端
│   ├── main.go               # 入口文件
│   ├── config/               # 配置包
│   │   └── config.go         # 配置加载逻辑
│   ├── models/               # 数据库模型
│   ├── handlers/             # HTTP 处理器
│   ├── middleware/           # 中间件 (NTLM 认证、请求日志)
│   └── router/               # 路由定义
├── frontend/                 # Vue 前端 (纯 HTML/JS/CSS)
│   └── index.html            # 单页应用入口
├── config/                   # 全局配置文件目录
│   └── config.yaml           # 应用配置
├── data/                     # SQLite 数据库文件 (.db)
├── tests/                    # 测试文件
├── init.bat                  # 初始化脚本
├── start.bat                 # 启动脚本
├── CLAUDE.md                 # Claude 开发指南
└── 启动指南.md               # 中文启动说明
```

## 开发流程

### 初始化环境
```bash
init.bat
```

### 启动后端
```bash
cd backend
go run main.go
```

### 启动前端
```bash
# 纯静态文件，直接双击 index.html 或在浏览器打开
# 如需本地服务器：
npx serve frontend -p 8080
```

## 数据库配置

- 默认路径：`data/survey.db`
- 配置在 `config/config.yaml`

## 关键配置

### NTLM 认证 (开发模式)
- 配置文件中的 `auth.mode: mock` 启用开发模式
- 测试账号：`test_user` / `password123`

### 数据库连接
```yaml
database:
  path: data/survey.db
  max_conn: 5
  timeout_ms: 3000
```

## 构建部署

### Windows 单文件 exe
```bash
cd backend
GOOS=windows GOARCH=amd64 go build -o survey.exe .
```

### 注册为 Windows 服务
```bash
# 使用 NSSM (Non-Sucking Service Manager)
nssm install survey.exe -ApplicationPath .
nssm start survey
```

## 初始化

运行 `init.bat` 创建项目结构并初始化 Go module：
- 创建目录：backend, frontend, config, data, tests
- 初始化 Go module: `go mod init survey`

## 注意事项

1. Go 需手动安装：`C:\go\go1.23.5.windows-amd64.msi`
2. 启动前需设置 PATH：`set PATH=C:\go\bin;%PATH%`
3. SQLite 写入需独占锁，避免并发写冲突
4. 生产环境建议配置 `auth.mode: ntlm` 启用真实域认证
5. 开发模式使用 `auth.mode: mock`，测试账号：test_user/password123

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **survey** (799 symbols, 1929 relationships, 68 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> If any GitNexus tool warns the index is stale, run `npx gitnexus analyze` in terminal first.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `gitnexus_detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.

## Never Do

- NEVER edit a function, class, or method without first running `gitnexus_impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `gitnexus_rename` which understands the call graph.
- NEVER commit changes without running `gitnexus_detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/survey/context` | Codebase overview, check index freshness |
| `gitnexus://repo/survey/clusters` | All functional areas |
| `gitnexus://repo/survey/processes` | All execution flows |
| `gitnexus://repo/survey/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
