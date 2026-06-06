# CLAUDE.md

## 规则

- **Context7**: 写任何第三方库代码前（ECharts、Vue 3、ASP.NET等），先用 Context7 查最新文档。
- **先查影响**: 编辑任何符号前，跑 `gitnexus_impact` 报告波及范围。HIGH/CRITICAL 务必警示。
- **提交前检测**: 提交前跑 `gitnexus_detect_changes()`。
- **OpenWolf**: 读文件前查 `.wolf/anatomy.md`。写代码前查 `.wolf/cerebrum.md`。
- **中文**: 对话、注释一律简体中文。

## 技术栈

- **后端**: ASP.NET C# (IHttpHandler) — 单 `.ashx` 文件，零 NuGet，纯 .NET 4.8
- **前端**: Vue 3 + ECharts（本地 vendor 文件，无 CDN，无构建）
- **数据库**: JSON 文件 + 原子写 + 文件锁 (`data/survey.json`)
- **认证**: IIS Windows 认证 (NTLM)，域用户自动识别
- **端口**: 80 (IIS)

## 目录

```
survey/
├── asp/api.ashx          # 后端 — 全部 HTTP 处理
├── web/                  # Vue 3 单页
│   ├── index.html
│   ├── css/style.css
│   └── js/
│       ├── app.js        # Vue 应用 + 路由
│       ├── api.js        # API 请求封装
│       ├── i18n.js       # 中英文切换
│       └── components/   # 问卷填写、统计、管理面板、设计器
├── data/survey.json      # JSON 数据库
├── config.json           # 初始管理员配置
├── sync-offline.bat      # 同步到离线部署包
├── web.config            # IIS 配置
└── offline-package/      # 离线部署包（含 install.bat 智能安装/更新）
```

## API 路由

全部通过 `GET/POST /asp/api.ashx?path=<route>`:

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | health | 健康检查 |
| GET | me | 当前用户 (username, is_admin) |
| GET | surveys/{id} | 已发布问卷详情 |
| POST | surveys/{id}/submit | 提交答卷 |
| GET | surveys/{id}/stats | 问卷统计 |
| GET/POST/PUT/DELETE | admin/surveys[/{id}] | 问卷 CRUD（管理员） |
| POST/PUT/DELETE | admin/surveys/{id}/questions[/{qid}] | 题目 CRUD |
| PUT | admin/surveys/{id}/questions/reorder | 重排题目 |
| GET | admin/surveys/{id}/export | CSV 导出 (UTF-8 BOM) |

## 认证

- IIS 从 `LOGON_USER` → `AUTH_USER` → `REMOTE_USER` 提取用户名
- 管理员：用户名在 `survey.json` 或 `config.json` 的 `admins[]` 数组中
- 不开放匿名访问（IIS Windows 认证为必须）

## 数据库 (JSON)

```json
{
  "surveys": [{ "id", "title", "description", "status": "draft|published|closed", "is_anonymous", "deadline", "created_at", "updated_at" }],
  "questions": [{ "id", "survey_id", "title", "type": "single|multi|text", "required", "char_limit", "sort_order" }],
  "options": [{ "id", "question_id", "content", "sort_order" }],
  "submissions": [{ "id", "survey_id", "username", "submitted_at" }],
  "answers": [{ "id", "submission_id", "question_id", "value" }],
  "admins": [{ "id", "username", "created_at" }]
}
```

## 常用命令

| 任务 | 命令 |
|------|------|
| 安装 | `offline-package\install.bat`（管理员权限） |
| 健康检查 | `curl http://localhost/asp/api.ashx?path=health` |
| 用户信息 | `curl http://localhost/asp/api.ashx?path=me` |
| 重启 IIS | `iisreset` |
| 查看数据 | `type data\survey.json` |

## 关键事项

1. **无构建步骤** — 前端纯 HTML/JS/CSS，后端 IIS 首次请求时编译
2. **C# 5 兼容** — 使用 Windows Server 默认编译器
3. **离线部署** — 零外部依赖
4. **原子写** — JSON 使用临时文件 + 重命名模式保证并发安全
5. **CSV 导出** — UTF-8 BOM 编码，Excel 友好
6. **仅 Windows** — 依赖 IIS + Windows 认证

## GitNexus

项目已索引：**survey**（799 符号、1929 关联、68 流程）

| 资源 | 用途 |
|------|------|
| `gitnexus://repo/survey/context` | 概览、检查新鲜度 |
| `gitnexus://repo/survey/processes` | 全部执行流程 |
| `gitnexus://repo/survey/process/{name}` | 逐步执行追踪 |

## 安全

- 认证依赖 IIS Windows 认证 (NTLM/Kerberos)
- 管理员校验：简单字符串比对
- 无 CSRF token（内网问卷系统可接受）
- 输入校验：基础校验（如仅已发布问卷可答卷）

## 迁移

- 复制 `data/survey.json` + `config.json` 到新服务器
- 运行 `offline-package\install.bat` 重建 IIS 站点
- 操作前务必备份 `survey.json`
