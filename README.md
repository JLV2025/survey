# 内部调查系统 / Internal Survey System

轻量级企业调查系统，ASP.NET C# 后端 (IHttpHandler) + Vue 3 前端。
IIS 原生 Windows 集成认证，零编译部署，完全离线安装。

---

## 功能特点 / Features

- **问卷设计器**：创建/编辑/删除问卷，支持单选题、多选题、文本题
- **拖拽设计**：题型面板拖拽到画布创建题目，画布内拖拽排序
- **发布锁定**：已发布问卷题目不可编辑，防止数据不一致
- **分步填写**：受访者以分步向导模式填写，草稿自动保存到 localStorage
- **域认证**：IIS Windows Authentication，域用户自动识别，无需登录
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
| 匿名用户 | 无访问权限（IIS 层拒绝） |

## 技术栈 / Tech Stack

| 层 Layer | 技术 Technology |
|---|---|
| 后端 Backend | ASP.NET C# 4.8 (IHttpHandler, 单文件 .ashx) |
| 前端 Frontend | Vue 3 + ECharts 5（本地 vendor，无 CDN） |
| 存储 Storage | JSON 文件（原子写入 + 文件锁） |
| 认证 Auth | IIS Windows Authentication（NTLM/Kerberos） |
| 导出 Export | CSV (UTF-8 BOM) |
| 部署 Deploy | 完全离线，零外部依赖 |

## 架构 / Architecture

```
survey/
├── asp/
│   └── api.ashx                  # 后端 API (单文件 C# IHttpHandler)
├── web/
│   ├── index.html                # 前端入口
│   ├── logo.gif
│   ├── css/
│   │   └── style.css
│   └── js/
│       ├── api.js                # API 调用封装
│       ├── app.js                # Vue 3 路由 + 入口
│       ├── i18n.js               # 国际化 (zh/en)
│       ├── components/
│       │   ├── survey-fill.js    # 问卷填写（分步向导）
│       │   ├── survey-stats.js   # 统计结果（饼图 + 文字列表）
│       │   ├── admin-dashboard.js    # 管理员概览
│       │   ├── admin-survey-list.js  # 问卷管理（创建/编辑元信息）
│       │   ├── admin-users.js        # 管理员管理（增删）
│       │   └── survey-designer.js    # 拖拽问卷设计器
│       └── vendor/
│           ├── vue.global.prod.js
│           └── echarts.min.js
├── data/
│   └── survey.json               # 数据库 (JSON 文件)
├── config.json                   # 初始管理员配置
├── web.config                    # IIS 配置
├── install.bat                   # 一键安装脚本
├── setup-iis.ps1                 # IIS 配置 PowerShell 脚本
└── offline-package/              # 离线部署包（含 UPDATE.md）
```

## 安装部署 / Deployment

### 前提条件
- Windows Server 2016/2019/2022
- IIS 已安装（Web Server + Windows Authentication + ASP.NET 4.8）
- 已加入域（可选，仅使用域认证时需要）

### 一键安装（推荐）
1. 以 **管理员身份** 运行 `install.bat`
2. 修改 `config.json`，设置 `initial_admin`：
   ```json
   { "initial_admin": "your_domain_username" }
   ```
   （支持逗号分隔多个管理员，支持 `DOMAIN\user` 和 `user` 两种格式）
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
appcmd add site /name:"Survey" /physicalPath:"C:\inetpub\wwwroot" /bindings:"http/*:80:"
appcmd set app "Survey/" /applicationPool:"Survey"

:: 4. 启用 Windows 认证
appcmd set config "Survey" /section:windowsAuthentication /enabled:true
appcmd set config "Survey" /section:anonymousAuthentication /enabled:false
```

### 验证安装
```
curl http://localhost/asp/api.ashx?path=health
```
预期返回：`{"ok":true,"data":"OK"}`

## IIS 认证说明 / Auth Configuration

`web.config` 最终配置：
- `windowsAuthentication enabled="true"` — IIS 提取域用户身份
- `anonymousAuthentication enabled="false"` — 拒绝未认证请求
- `<allow users="*" />` — ASP.NET 层放行（应用层 RequireAdmin 保护管理路由）

### 为什么不用 `<deny users="?" />`？
NTLM 握手对 GET 请求有效，但对 DELETE/PUT/POST 请求可能失败导致 401 循环。
改为 `<allow users="*" />` 配合应用层权限检查，确保所有 HTTP 方法正常工作。

## 更新部署 / Update

详见 `offline-package/UPDATE.md`。简要步骤：
```bat
net stop w3svc
xcopy "新版本\web\*" "C:\inetpub\wwwroot\web\" /E /Y
xcopy "新版本\asp\*" "C:\inetpub\wwwroot\asp\" /E /Y
copy "新版本\web.config" "C:\inetpub\wwwroot\web.config" /Y
net start w3svc
```
（保留 `data/survey.json` 和 `config.json` 不覆盖）

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

- 后端使用 `.ashx` (IHttpHandler)，兼容 C# 5.0（Windows Server 自带编译器）
- 零 NuGet 包依赖，纯 .NET Framework 4.8 内置 API
- JSON 序列化/反序列化手写实现，无第三方库
- 文件写入使用 tmp + rename 原子操作 + 文件锁，支持并发读写
- 前端 Vue 3 + ECharts 已打包为单文件 vendor，无需 npm/yarn
- **已发布问卷题目锁定**：前后端双重保护，已发布状态禁止增删改排序题目
