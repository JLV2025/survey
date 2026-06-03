# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Internal Survey System - Lightweight enterprise survey platform deployed on Windows Server 2022.
- **Backend**: ASP.NET C# (IHttpHandler) - single .ashx file, no NuGet dependencies
- **Frontend**: Vue 3 + ECharts (bundled vendor files, no CDN)
- **Database**: JSON file with atomic write + file locking
- **Authentication**: IIS Windows Authentication (domain users auto-identified)
- **Port**: 80 (IIS default)

## Architecture

```
survey/
├── asp/                    # Backend API (single .ashx file)
│   └── api.ashx            # All HTTP handlers (CRUD for surveys, questions, submissions)
├── web/                    # Frontend Vue 3 SPA
│   ├── index.html          # Single entry point
│   ├── css/style.css       # Tailwind-like utility-first CSS
│   └── js/
│       ├── app.js          # Vue 3 router + main app
│       ├── api.js          # API request wrapper
│       ├── i18n.js         # i18n (zh/en)
│       └── components/     # Vue components
│           ├── survey-fill.js         # Survey fill wizard
│           ├── survey-stats.js        # ECharts stats page
│           ├── admin-dashboard.js     # Admin panel entry
│           ├── admin-survey-list.js   # Survey CRUD
│           └── survey-designer.js     # Drag-drop designer
├── data/                   # JSON database
│   └── survey.json        # All data (surveys, questions, submissions)
├── config.json             # Initial admin configuration
├── install.bat             # One-click offline installer
├── web.config              # IIS configuration
└── offline-package/        # Offline deployment package
```

## Backend (ASP.NET C#)

### Single-File API Handler
- **File**: `asp/api.ashx`
- **Pattern**: `IHttpHandler` with `ProcessRequest(HttpContext)`
- **Routing**: Path-based routing via `path` query string
- **JSON**: Hand-rolled parser/serializer (C# 5 compatible)
- **No dependencies**: Pure .NET Framework 4.8 built-in APIs

### API Routes
All routes via `/asp/api.ashx?path=<route>`:

| Method | Path | Description |
|--------|------|-------------|
| GET | health | Health check |
| GET | me | Current user info (username, is_admin) |
| GET | check-admin | Check admin permission |
| GET | surveys/{id} | Get published survey |
| GET | surveys/{id}/check | Check if submitted |
| POST | surveys/{id}/submit | Submit response |
| GET | surveys/{id}/stats | Get statistics |
| GET | admin/surveys | List surveys (admin) |
| POST | admin/surveys | Create survey (admin) |
| PUT | admin/surveys/{id} | Update survey (admin) |
| DELETE | admin/surveys/{id} | Delete survey (admin) |
| POST | admin/surveys/{id}/questions | Create question |
| PUT | admin/surveys/{id}/questions/{qid} | Update question |
| DELETE | admin/surveys/{id}/questions/{qid} | Delete question |
| PUT | admin/surveys/{id}/questions/reorder | Reorder questions |
| GET | admin/surveys/{id}/export | CSV export |

### Authentication
- **NTLM**: Extracts username from `LOGON_USER`, `AUTH_USER`, or `REMOTE_USER`
- **Admin check**: Compares against `admins` array in `survey.json` or `config.json` initial_admin
- **Anonymous**: Disabled (IIS Windows Authentication required)

### Data Storage
- **File**: `data/survey.json`
- **Atomic writes**: tmp file + rename + file lock
- **Empty DB**: Returns empty arrays for surveys, questions, options, submissions, answers, admins

## Frontend (Vue 3)

### Single HTML Entry
- **File**: `web/index.html`
- **No build**: CDN-free, all vendor files bundled locally
- **Vue 3**: `vue.global.prod.js` (production build)
- **ECharts**: `echarts.min.js` (bundled)

### Vue Router
- **Routes**: Home, Admin, Survey Fill, Survey Stats, Survey Designer
- **Navigation**: Click nav-brand to go home, admin button for admin panel
- **Components**: Dynamically rendered via `<component :is="currentView">`

### i18n
- **Languages**: Chinese (zh), English (en)
- **Implementation**: Simple dictionary in `i18n.js`
- **Toggle**: Buttons in nav-right

## Database Schema (JSON)

```json
{
  "surveys": [
    {
      "id": "uuid",
      "title": "Survey Title",
      "description": "Description",
      "status": "draft|published|closed",
      "is_anonymous": false,
      "deadline": "ISO8601",
      "created_at": "ISO8601",
      "updated_at": "ISO8601"
    }
  ],
  "questions": [
    {
      "id": "uuid",
      "survey_id": "uuid",
      "title": "Question Title",
      "type": "single|multi|text",
      "required": true,
      "char_limit": 0,
      "sort_order": 0
    }
  ],
  "options": [
    {
      "id": "uuid",
      "question_id": "uuid",
      "content": "Option Text",
      "sort_order": 0
    }
  ],
  "submissions": [
    {
      "id": "uuid",
      "survey_id": "uuid",
      "username": "domain\\user",
      "submitted_at": "ISO8601"
    }
  ],
  "answers": [
    {
      "id": "uuid",
      "submission_id": "uuid",
      "question_id": "uuid",
      "value": "Answer Value"
    }
  ],
  "admins": [
    {
      "id": "uuid",
      "username": "domain\\admin",
      "created_at": "ISO8601"
    }
  ]
}
```

## Development Workflow

### Verify Installation
```bash
# Health check
curl http://localhost/asp/api.ashx?path=health
# Expected: {"ok":true,"data":"OK"}

# User info
curl http://localhost/asp/api.ashx?path=me
# Expected: {"ok":true,"data":{"username":"domain\\user","is_admin":false}}
```

### Common Commands

| Task | Command |
|------|---------|
| Install | `install.bat` (as Administrator) |
| Restart IIS | `iisreset` |
| Health check | `curl http://localhost/asp/api.ashx?path=health` |
| View data | `type data\survey.json` |
| Edit config | `notepad config.json` |

## Key Files

| File | Purpose |
|------|--------|
| `asp/api.ashx` | Backend API - all HTTP handlers |
| `web/index.html` | Frontend entry point |
| `web/js/app.js` | Vue 3 app + router |
| `web/js/components/survey-fill.js` | Survey fill wizard component |
| `web/js/components/survey-designer.js` | Drag-drop survey designer |
| `data/survey.json` | All data (database) |
| `config.json` | Initial admin configuration |
| `install.bat` | Offline installer script |
| `web.config` | IIS configuration |

## Important Notes

1. **No build step**: Frontend is pure HTML/JS/CSS, no npm/yarn required
2. **C# 5 compatible**: All backend code works with Windows Server default compiler
3. **Offline deployment**: No external NuGet packages or CDN dependencies
4. **Windows-only**: Requires IIS with Windows Authentication enabled
5. **Atomic writes**: JSON file uses tmp+rename pattern for concurrent access safety
6. **CSV export**: UTF-8 BOM encoding for Excel compatibility

## Security Considerations

- **Authentication**: Relies on IIS Windows Authentication (NTLM/Kerberos)
- **Admin check**: Simple string comparison against `admins` array
- **No CSRF**: GET/POST without CSRF tokens (acceptable for internal survey system)
- **Input validation**: Basic validation in handlers (e.g., survey must be published to accept submissions)

## Migration Notes

- **Database**: Copy `data/survey.json` to new server
- **Config**: Copy `config.json` with initial_admin settings
- **IIS**: Run `install.bat` to recreate site and enable Windows auth
- **Data integrity**: Always backup `survey.json` before operations
