# 内部调查系统 / Internal Survey System

轻量级企业调查系统。Vue 3 前端 + C# HttpListener 独立服务后端。

Windows 集成认证（NTLM/Kerberos），**域用户打开网页自动识别账号，无需输入密码**。
JSON 文件存储，完全离线部署，零外部依赖（仅 .NET Framework 4.8，系统自带）。

---

## 功能特点 / Features

- **问卷设计器**：创建/编辑/删除问卷，支持单选题、多选题、文本题
- **拖拽设计**：题型面板拖拽到画布创建题目，画布内拖拽排序
- **发布锁定**：已发布问卷题目不可编辑，防止数据不一致
- **分步填写**：受访者以分步向导模式填写，草稿自动保存到 localStorage
- **域认证**：Windows 集成认证（NTLM），域用户自动识别，无需登录
- **防重复提交**：基于用户名的提交锁定，已提交者查看统计页面
- **匿名调查**：匿名模式下不显示提交者信息，导出不含用户名列
- **实时统计**：ECharts 饼图 + 文字答案列表，每 30 秒自动刷新
- **CSV 导出**：UTF-8 BOM 编码，Excel 直接打开
- **多语言**：简体中文 / English 界面切换
- **管理员白名单**：独立管理员管理页面 + config.json 初始管理员配置
- **级联删除**：删除问卷时自动清理关联的问题/选项/提交/回答
- **后端保护**：已发布问卷在后端阻止问题增删改排序

## 权限模型 / Permission Model

| 角色 | 权限 |
|------|------|
| 域用户（自动识别） | 填写已发布问卷、查看统计结果 |
| 管理员 | 创建/编辑/删除问卷、设计题目、发布/关闭、导出 CSV、管理管理员 |
| 匿名用户 | 无访问权限（认证层直接拒绝，401） |

## 技术栈 / Tech Stack

| 层 Layer | 技术 Technology |
|---|---|
| 后端 Backend | C# 4.8 HttpListener 独立服务（`http-server/SurveyServer.cs` 单文件） |
| 前端 Frontend | Vue 3 + ECharts 5（本地 vendor，无 CDN） |
| 存储 Storage | JSON 文件（原子写入 + 文件锁） |
| 认证 Auth | Windows 集成认证（NTLM/Kerberos，浏览器自动发凭据） |
| 导出 Export | CSV (UTF-8 BOM) |
| 部署 Deploy | 完全离线，零外部依赖（.NET Framework 4.8 系统自带，csc.exe 离线编译） |

## 架构 / Architecture

```
survey/
├── http-server/                 # 后端服务（推荐，全部逻辑在单文件）
│   ├── SurveyServer.cs          # 认证 + API + 静态文件（单文件 C#）
│   ├── SurveyServer.exe.config  # 监听配置（默认 http://+:80/，可换端口）
│   └── README.md
├── web/                         # 前端（Vue 3 单页）
│   ├── index.html               # 前端入口
│   ├── css/style.css
│   └── js/
│       ├── api.js               # API 请求封装
│       ├── app.js               # Vue 3 路由 + 入口
│       ├── i18n.js              # 国际化 (zh/en)
│       ├── components/          # 6 个 Vue 组件
│       └── vendor/              # Vue 3 + ECharts（本地文件）
├── index.html                   # 部署入口（部署时放根目录）
├── data/
│   └── survey.json              # 数据库 (JSON 文件)
├── config.json                  # 初始管理员配置
├── install.bat                  # 一键安装（离线编译 + 服务 + 防火墙）
├── uninstall.bat                # 卸载
└── offline-package/             # 离线部署包（拷到服务器直接安装）
```

> 部署时 `SurveyServer.exe`（install.bat 自动编译生成）与 `web/`、`data/`、
> `config.json`、`index.html` 同级。

## 安装部署 / Deployment

### 前提条件

- Windows Server 2016/2019/2022（或 Windows 10/11 工作站）
- **.NET Framework 4.8**（系统自带或已安装）
- 计算机与服务器在同一 **AD 域**（或信任域），用于自动识别账号
- 服务器无需联网（全部离线）

### 一键安装（推荐）

1. 将项目目录（或 `offline-package/`）拷贝到服务器
2. 以 **管理员身份** 运行 **`install.bat`**
3. 脚本自动完成：
   - 用系统自带 csc.exe **离线编译** `SurveyServer.exe`
   - 注册 URL ACL（`http://+:80/`）
   - 创建并启动 Windows 服务 **`SurveySvc`**（开机自启）
   - 防火墙放行 80 端口
4. 编辑 `config.json` 设置初始管理员：
   ```json
   { "initial_admin": "your_domain_username" }
   ```
   （小写域账号，可逗号分隔多个，支持 `DOMAIN\user` 和 `user` 两种格式）
5. **用主机名访问**：`http://服务器主机名/`

> 换端口：编辑 `SurveyServer.exe.config` 的 `listen` 值（如 `http://+:8080/`）后重启服务。

### 手动编译（可选）

```bat
"%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /codepage:65001 /r:System.ServiceProcess.dll /out:SurveyServer.exe http-server\SurveyServer.cs
```

### 验证安装

```bat
:: 本机验证（NTLM 自动认证，显示你的域账号）
curl --ntlm -u : http://localhost/asp/diag.ashx

:: 浏览器验证
http://<服务器主机名>/asp/diag.ashx
:: 预期显示: Identity.Name: [DOMAIN\账号]
```

## 认证说明 / Auth Configuration

- 服务强制 `IntegratedWindowsAuthentication`：未认证请求返回 401 +
  `WWW-Authenticate: Negotiate`，浏览器自动携带当前 Windows 域账号
- 后端从 `ctx.User.Identity.Name` 直接取得 `DOMAIN\user`，去掉前缀得用户名
- 管理员名单：`config.json` 的 `initial_admin` + 后台 `admins[]`（存于 `data/survey.json`）
- 未认证请求一律 401，身份无法伪造

**重要**：浏览器（Chrome/Edge）默认只对"本地 Intranet"区域的站点自动发送域凭据。
**请用主机名/域名访问**（如 `http://survey-server/`），**不要用 IP 地址**，
否则浏览器不发送凭据，将无法取得账号（401）。

## 更新部署 / Update

详见 `UPDATE.md`。核心：

```bat
sc stop SurveySvc
:: 覆盖 web/、SurveyServer.exe（保留 data/ 与 config.json）
sc start SurveySvc
```

## 跨服务器迁移

1. 将项目目录完整复制到新服务器（含 `data/survey.json`、`config.json`）
2. 管理员运行 `install.bat`
3. 数据直接可用（JSON 文件即数据库）

## API 文档 / API Reference

所有 API 通过单入口访问：

```
GET/POST/PUT/DELETE /asp/api.ashx?path=<route>
```

### 公开端点

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | health | 健康检查 |
| GET | me | 当前用户信息（用户名 + 是否管理员） |
| GET | check-admin | 检查管理员权限 |
| GET | surveys/{id} | 获取已发布问卷（含题目和选项） |
| GET | surveys/{id}/check | 检查是否已提交 |
| POST | surveys/{id}/submit | 提交答卷 |
| GET | surveys/{id}/stats | 统计结果（仅已发布问卷） |

### 管理端点 (需管理员权限)

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | admin/surveys | 问卷列表 |
| POST | admin/surveys | 创建问卷 |
| PUT | admin/surveys/{id} | 更新问卷元信息 |
| DELETE | admin/surveys/{id} | 删除问卷（级联清理） |
| PUT | admin/surveys/{id}/status | 更新状态 (draft/published/closed) |
| POST | admin/surveys/{id}/questions | 创建题目（已发布问卷拒绝） |
| PUT | admin/surveys/{id}/questions/{qid} | 更新题目（已发布问卷拒绝） |
| DELETE | admin/surveys/{id}/questions/{qid} | 删除题目（已发布问卷拒绝） |
| PUT | admin/surveys/{id}/questions/reorder | 排序题目（已发布问卷拒绝） |
| GET | admin/surveys/{id}/submissions | 提交记录 |
| GET | admin/surveys/{id}/export | CSV 导出 |
| GET | admin/users | 管理员列表 |
| POST | admin/users | 添加管理员 |
| DELETE | admin/users/{id} | 删除管理员 |

## 数据库结构 / Database Schema

```json
{
  "surveys": [{"id": "uuid", "title": "...", "description": "...", "status": "draft|published|closed", "is_anonymous": false, "deadline": "", "created_at": "...", "updated_at": "..."}],
  "questions": [{"id": "uuid", "survey_id": "uuid", "title": "...", "type": "single|multiple|text|textarea", "required": true, "char_limit": 0, "sort_order": 1}],
  "options": [{"id": "uuid", "question_id": "uuid", "content": "...", "sort_order": 0}],
  "submissions": [{"id": "uuid", "survey_id": "uuid", "username": "domain\\user", "submitted_at": "..."}],
  "answers": [{"id": "uuid", "submission_id": "uuid", "question_id": "uuid", "value": "..."}],
  "admins": [{"id": "uuid", "username": "username", "created_at": "..."}]
}
```

## 技术说明 / Notes

- C# 5 兼容（Windows Server 自带 csc.exe 可编译），零 NuGet 包，服务器离线可用
- 认证、静态文件、API 全部由单个 `SurveyServer.exe` 提供
- JSON 序列化/反序列化手写实现，无第三方库
- 文件写入使用 tmp + rename 原子操作 + 文件锁，支持并发读写
- 前端 Vue 3 + ECharts 已打包为单文件 vendor，无需 npm/yarn
- **已发布问卷题目锁定**：前后端双重保护，已发布状态禁止增删改排序题目
