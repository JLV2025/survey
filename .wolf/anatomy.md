# anatomy.md

> Auto-maintained by OpenWolf. Last scanned: 2026-06-02T06:32:17.714Z
> Files: 56 tracked | Anatomy hits: 0 | Misses: 0

## ./

- `.gitignore` — Git ignore rules (~107 tok)
- `build-offline.bat` (~942 tok)
- `CLAUDE.md` — CLAUDE.md (~198 tok)
- `config.json` (~9 tok)
- `go.mod` — Go module definition (~143 tok)
- `main.go` — Struct: Config (~1124 tok)
- `README.html` — 内部调查系统 / Internal Survey System (~2010 tok)
- `README.md` — Project documentation (~1455 tok)
- `requests.md` — 一、项目概述 (~586 tok)
- `setup-iis.ps1` (~909 tok)
- `web.config` (~306 tok)

## .claude/

- `settings.json` (~583 tok)

## .claude/agents/

- `security-reviewer.md` — Focus Areas (~277 tok)
- `ui-reviewer.md` — Focus Areas (~272 tok)

## .claude/rules/

- `openwolf.md` (~313 tok)

## .claude/skills/api-doc/

- `SKILL.md` — 步骤 (~104 tok)

## .claude/skills/setup-dev/

- `SKILL.md` — 前置条件 (~112 tok)

## C:/Users/jingl/.claude/plans/

- `cached-marinating-dragonfly.md` — Classic ASP 重写方案 (~1437 tok)
- `delightful-growing-lantern.md` — 问卷填写页静默获取 NTLM 用户名 (~236 tok)
- `requests-md-90-requests-md-sparkling-hopcroft.md` — Implementation Plan: 内部调查系统 (Survey) (~1657 tok)

## asp/

- `api.asp` (~9234 tok)
- `json.asp` (~2124 tok)

## internal/handler/

- `admin.go` — HTTP handlers: GetMe, CheckAdmin, GetSurvey, CheckSubmitted, SubmitSurvey (~1818 tok)
- `export.go` — HTTP handlers: ExportExcel (~1065 tok)
- `helpers.go` — HTTP handlers: writeJSON (~123 tok)
- `question.go` — HTTP handlers: CreateQuestion, UpdateQuestion, DeleteQuestion, ReorderQuestions (~575 tok)
- `stats.go` — HTTP handlers: GetStats (~327 tok)
- `submission.go` — HTTP handlers: SubmitSurvey (~654 tok)
- `survey.go` — HTTP handlers: GetSurvey, CheckSubmitted, ListAdminSurveys, CreateAdminSurvey, UpdateAdminSurvey (~1162 tok)

## internal/middleware/

- `auth.go` — AuthMiddleware, GetUsername, NormalizeUsername (~664 tok)
- `ntlm.go` — Struct: ntlmField (~1109 tok)

## internal/model/

- `models.go` — Struct: Survey (~670 tok)

## internal/store/

- `admin.go` (~4 tok)
- `db.go` — Struct: JSONFileStore (~3030 tok)
- `submission.go` (~4 tok)
- `survey.go` (~4 tok)

## offline-package/

- `config.json` (~9 tok)
- `install.bat` (~394 tok)
- `setup-iis.ps1` (~1235 tok)
- `web.config` (~209 tok)
- `升级说明.md` — 服务器更新说明 (~520 tok)
- `安装步骤.html` — 内部调查系统 - 离线安装指南 (~2626 tok)

## offline-package/api/

- `me.asp` (~358 tok)

## offline-package/web/js/

- `i18n.js` — I18N: t, setLang (~1447 tok)

## offline-package/web/js/components/

- `admin-dashboard.js` — 管理员面板 — 主入口 (~1187 tok)
- `survey-fill.js` — 问卷填写 — 分步向导 (~2289 tok)

## web/

- `index.html` — 内部调查系统 (~465 tok)

## web/css/

- `style.css` — Styles: 75 rules, 15 vars (~2013 tok)

## web/js/

- `api.js` — API 请求封装 (~1146 tok)
- `app.js` — Vue 3 应用入口 + 路由 (~1239 tok)
- `i18n.js` — I18N: t, setLang (~1447 tok)

## web/js/components/

- `admin-dashboard.js` — 管理员面板 — 主入口 (~1187 tok)
- `admin-survey-list.js` — 管理员 — 问卷列表（创建/编辑问卷信息） (~2818 tok)
- `survey-designer.js` — 拖拽问卷设计器 (~3843 tok)
- `survey-fill.js` — 问卷填写 — 分步向导 (~2289 tok)
- `survey-stats.js` — 统计页 — ECharts 饼图 + 30s 轮询 (~1026 tok)
