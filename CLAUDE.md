# CLAUDE.md

## 规则

- **Context7**: 写任何第三方库代码前（ECharts、Vue 3、ASP.NET等），先用 Context7 查最新文档。
- **先查影响**: 编辑任何符号前，跑 `gitnexus_impact` 报告波及范围。HIGH/CRITICAL 务必警示。
- **提交前检测**: 提交前跑 `gitnexus_detect_changes()`。
- **OpenWolf**: 读文件前查 `.wolf/anatomy.md`。写代码前查 `.wolf/cerebrum.md`。
- **中文**: 对话、注释一律简体中文。

## 技术栈

- **后端**: C# 4.8 HttpListener 独立服务 — `http-server/SurveyServer.cs` 单文件，零 NuGet，纯 .NET 4.8（系统自带 csc.exe 离线编译）
- **前端**: Vue 3 + ECharts（本地 vendor 文件，无 CDN，无构建）
- **数据库**: JSON 文件 + 原子写 + 文件锁 (`data/survey.json`)
- **认证**: Windows 集成认证 (NTLM/Kerberos)，域用户自动识别，免输入密码
- **端口**: 80（HttpListener 服务 `SurveySvc`）

## 目录

```
survey/
├── http-server/              # 后端 — HttpListener 独立服务
│   ├── SurveyServer.cs       # 全部逻辑：认证 + API + 静态文件（单文件 C#）
│   ├── SurveyServer.exe.config  # 监听配置（默认 http://+:80/）
│   └── README.md
├── web/                      # Vue 3 单页
│   ├── index.html
│   ├── css/style.css
│   └── js/
│       ├── app.js            # Vue 应用 + 路由
│       ├── api.js            # API 请求封装
│       ├── i18n.js           # 中英文切换
│       └── components/       # 问卷填写、统计、管理面板、设计器
├── index.html                # 部署入口（部署时放根目录）
├── data/survey.json          # JSON 数据库
├── config.json               # 初始管理员配置
├── install.bat               # 一键安装（编译 + 服务 + 防火墙）
├── uninstall.bat             # 卸载
├── sync-offline.bat          # 同步到离线部署包
└── offline-package/          # 离线部署包（拷到服务器直接安装）
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

- HttpListener 强制 `IntegratedWindowsAuthentication`，从 `ctx.User.Identity.Name` 直接取 `DOMAIN\user`（免输入密码）
- 管理员：用户名在 `config.json` 的 `initial_admin` 或 `survey.json` 的 `admins[]` 数组中
- 不开放匿名访问（未认证请求返回 401）
- **浏览器必须用主机名/域名访问**（IP 地址不触发 NTLM 凭据发送）

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
| 安装 | `install.bat`（管理员权限） |
| 卸载 | `uninstall.bat`（管理员权限） |
| 服务状态 | `sc query SurveySvc` |
| 重启服务 | `sc stop SurveySvc && sc start SurveySvc` |
| 健康检查 | `curl --ntlm -u : http://localhost/asp/api.ashx?path=health` |
| 用户信息 | `curl --ntlm -u : http://localhost/asp/api.ashx?path=me` |
| 认证诊断 | `curl --ntlm -u : http://localhost/asp/diag.ashx` |
| 离线编译后端 | `"%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /codepage:65001 /r:System.ServiceProcess.dll /out:SurveyServer.exe http-server\SurveyServer.cs` |
| 查看数据 | `type data\survey.json` |

## 关键事项

1. **前端无构建** — 纯 HTML/JS/CSS；后端需用系统 csc.exe 离线编译（`install.bat` 自动完成）
2. **C# 5 兼容** — 使用 Windows Server 默认编译器
3. **离线部署** — 零外部依赖，服务器无需联网
4. **原子写** — JSON 使用临时文件 + 重命名模式保证并发安全
5. **CSV 导出** — UTF-8 BOM 编码，Excel 友好
6. **仅 Windows** — 依赖 Windows 集成认证（HttpListener）
7. **API 路径兼容** — 前端调用 `/asp/api.ashx?path=`，由服务路由处理（非 IIS 文件路径）

## GitNexus

项目已索引：**survey**（799 符号、1929 关联、68 流程）

| 资源 | 用途 |
|------|------|
| `gitnexus://repo/survey/context` | 概览、检查新鲜度 |
| `gitnexus://repo/survey/processes` | 全部执行流程 |
| `gitnexus://repo/survey/process/{name}` | 逐步执行追踪 |

## 安全

- 认证依赖 Windows 集成认证 (NTLM/Kerberos)，从 `ctx.User.Identity.Name` 取账号
- 管理员校验：简单字符串比对（用户名去 `DOMAIN\` 前缀后小写比对）
- 未认证请求 401 拒绝；HTTP 层无明文口令传输
- 无 CSRF token（内网问卷系统可接受）
- 输入校验：基础校验（如仅已发布问卷可答卷）

## 迁移

- 复制 `data/survey.json` + `config.json` 到新服务器
- 运行 `install.bat` 重建服务
- 数据是 JSON 文件，复制即迁移；操作前务必备份 `survey.json`
