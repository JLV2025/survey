// API 请求封装
const BASE = '/api';

async function apiGet(path) {
  const res = await fetch(BASE + path);
  if (!res.ok) {
    let msg = 'Network error: ' + res.status;
    try { const b = await res.json(); if (b.message) msg = b.message; } catch (_) {}
    return { ok: false, message: msg };
  }
  return res.json();
}

async function apiPost(path, body) {
  const res = await fetch(BASE + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    let msg = 'Network error: ' + res.status;
    try { const b = await res.json(); if (b.message) msg = b.message; } catch (_) {}
    return { ok: false, message: msg };
  }
  return res.json();
}

async function apiPut(path, body) {
  const res = await fetch(BASE + path, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    let msg = 'Network error: ' + res.status;
    try { const b = await res.json(); if (b.message) msg = b.message; } catch (_) {}
    return { ok: false, message: msg };
  }
  return res.json();
}

async function apiDelete(path) {
  const res = await fetch(BASE + path, { method: 'DELETE' });
  if (!res.ok) {
    let msg = 'Network error: ' + res.status;
    try { const b = await res.json(); if (b.message) msg = b.message; } catch (_) {}
    return { ok: false, message: msg };
  }
  return res.json();
}

// ====== 用户 ======
function fetchMe() { return apiGet('/me'); }
function checkAdmin() { return apiGet('/check-admin'); }

// ====== 问卷（受访者端） ======
function fetchSurvey(id) { return apiGet('/surveys/' + id); }
function checkSubmitted(id) { return apiGet('/surveys/' + id + '/check'); }
function submitSurvey(id, answers) { return apiPost('/surveys/' + id + '/submit', { answers }); }
function fetchStats(id) { return apiGet('/surveys/' + id + '/stats'); }

// ====== 管理员 ======
function fetchAdminSurveys() { return apiGet('/admin/surveys'); }
function createSurvey(data) { return apiPost('/admin/surveys', data); }
function updateSurvey(id, data) { return apiPut('/admin/surveys/' + id, data); }
function deleteSurvey(id) { return apiDelete('/admin/surveys/' + id); }
function updateSurveyStatus(id, status) { return apiPut('/admin/surveys/' + id + '/status', { status }); }
function createQuestion(surveyId, data) { return apiPost('/admin/surveys/' + surveyId + '/questions', data); }
function updateQuestion(surveyId, qid, data) { return apiPut('/admin/surveys/' + surveyId + '/questions/' + qid, data); }
function deleteQuestion(surveyId, qid) { return apiDelete('/admin/surveys/' + surveyId + '/questions/' + qid); }
function reorderQuestions(surveyId, ids) { return apiPut('/admin/surveys/' + surveyId + '/questions/reorder', { ids }); }
function fetchSubmissions(surveyId) { return apiGet('/admin/surveys/' + surveyId + '/submissions'); }
function exportExcel(surveyId) {
  return fetch(BASE + '/admin/surveys/' + surveyId + '/export').then(r => {
    if (!r.ok) throw new Error('导出失败: ' + r.status);
    return r.blob();
  });
}
function fetchAdmins() { return apiGet('/admin/users'); }
function addAdmin(username) { return apiPost('/admin/users', { username }); }
function removeAdmin(id) { return apiDelete('/admin/users/' + id); }

// ====== 工具 ======
function getSurveyURL(id) {
  const base = location.origin + location.pathname.replace(/\/$/, '');
  return base + '#/fill/' + id;
}

function copyToClipboard(text) {
  if (navigator.clipboard && window.isSecureContext) {
    return navigator.clipboard.writeText(text).catch(() => {});
  }
  // fallback for HTTP
  const ta = document.createElement('textarea');
  ta.value = text;
  ta.style.position = 'fixed';
  ta.style.left = '-9999px';
  document.body.appendChild(ta);
  ta.select();
  const ok = document.execCommand('copy');
  document.body.removeChild(ta);
  if (!ok) throw new Error('复制失败');
}
