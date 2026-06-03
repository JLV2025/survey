<%@ Page Language="C#" %>
<%@ Import Namespace="System" %>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Web" %>
<%@ Import Namespace="System.Text" %>
<%@ Import Namespace="System.Collections.Generic" %>
<%@ Import Namespace="System.Linq" %>
<script runat="server">

void Page_Load() {
    try {
        Response.ContentType = "application/json";
        Response.Charset = "UTF-8";
        var path = Request.QueryString["path"] ?? Request.QueryString["__path"] ?? "";
        var method = Request.HttpMethod.ToUpperInvariant();
        Route(method, path);
    } catch (Exception ex) {
        Response.Write("{\"ok\":false,\"message\":\"server error: " + EscapeJson(ex.Message) + "\"}");
    }
}

void Route(string method, string path) {
    var seg = path.Split(new[] { '/' }, StringSplitOptions.RemoveEmptyEntries);
    var n = seg.Length;

    if (method == "GET" && path == "health") { WriteOk("OK"); return; }
    if (method == "GET" && path == "me") { HandleMe(); return; }
    if (method == "GET" && path == "check-admin") { HandleCheckAdmin(); return; }
    if (method == "GET" && n == 2 && seg[0] == "surveys") { HandleGetSurvey(seg[1]); return; }
    if (method == "GET" && n == 3 && seg[0] == "surveys" && seg[2] == "check") { HandleCheckSubmitted(seg[1]); return; }
    if (method == "POST" && n == 3 && seg[0] == "surveys" && seg[2] == "submit") { HandleSubmitSurvey(seg[1]); return; }
    if (method == "GET" && n == 3 && seg[0] == "surveys" && seg[2] == "stats") { HandleGetStats(seg[1]); return; }
    if (n > 0 && seg[0] == "admin") {
        if (!RequireAdmin()) return;
        if (method == "GET" && n == 1) { HandleListAdminSurveys(); return; }
        if (method == "POST" && n == 1) { HandleCreateAdminSurvey(); return; }
        if (method == "PUT" && n == 2) { HandleUpdateAdminSurvey(seg[1]); return; }
        if (method == "DELETE" && n == 2) { HandleDeleteAdminSurvey(seg[1]); return; }
        if (method == "PUT" && n == 3 && seg[2] == "status") { HandleUpdateSurveyStatus(seg[1]); return; }
        if (method == "POST" && n == 3 && seg[2] == "questions") { HandleCreateQuestion(seg[1]); return; }
        if (method == "PUT" && n == 4 && seg[2] == "questions") { HandleUpdateQuestion(seg[1], seg[3]); return; }
        if (method == "DELETE" && n == 4 && seg[2] == "questions") { HandleDeleteQuestion(seg[1], seg[3]); return; }
        if (method == "PUT" && n == 4 && seg[2] == "questions" && seg[3] == "reorder") { HandleReorderQuestions(seg[1]); return; }
        if (method == "GET" && n == 3 && seg[2] == "submissions") { HandleListSubmissions(seg[1]); return; }
        if (method == "GET" && n == 3 && seg[2] == "export") { HandleExportCSV(seg[1]); return; }
        if (method == "GET" && n == 2 && seg[1] == "users") { HandleListAdmins(); return; }
        if (method == "POST" && n == 2 && seg[1] == "users") { HandleAddAdmin(); return; }
        if (method == "DELETE" && n == 2 && seg[1] == "users") { HandleRemoveAdmin(seg[1]); return; }
        WriteErr("route not found"); return;
    }
    WriteErr("route not found");
}

string GetUsername() {
    var u = Request.ServerVariables["LOGON_USER"];
    if (string.IsNullOrEmpty(u)) u = Request.ServerVariables["AUTH_USER"];
    if (string.IsNullOrEmpty(u)) u = Request.ServerVariables["REMOTE_USER"];
    if (!string.IsNullOrEmpty(u) && u.Contains("\\")) u = u.Substring(u.IndexOf('\\') + 1);
    return (u ?? "").ToLower();
}

bool IsAdmin(string username) {
    if (string.IsNullOrEmpty(username)) return false;
    var db = ReadDB();
    object[] admins = db.ContainsKey("admins") ? (object[])db["admins"] : new object[0];
    foreach (var a in admins) {
        var d = (Dictionary<string, object>)a;
        if (string.Equals(Convert.ToString(d["username"]), username, StringComparison.OrdinalIgnoreCase))
            return true;
    }
    var cfg = LoadConfig();
    if (cfg.ContainsKey("initial_admin")) {
        var raw = Convert.ToString(cfg["initial_admin"] ?? "");
        if (!string.IsNullOrEmpty(raw)) {
            foreach (var item in raw.Split(',')) {
                var trimmed = item.Trim();
                if (trimmed.Contains("\\")) trimmed = trimmed.Substring(trimmed.IndexOf('\\') + 1);
                if (string.Equals(trimmed, username, StringComparison.OrdinalIgnoreCase)) return true;
            }
        }
    }
    return false;
}

bool RequireAdmin() {
    var u = GetUsername();
    if (string.IsNullOrEmpty(u)) { WriteErr("auth failed: no user identity"); return false; }
    if (!IsAdmin(u)) { WriteErr("no admin permission"); return false; }
    return true;
}

string DataPath() { 
    return System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "data", "survey.json");
}
string ConfigPath() { 
    return System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "config.json");
}

object _lock = new object();

Dictionary<string, object> ReadDB() {
    var path = DataPath();
    if (!File.Exists(path)) return EmptyDB();
    lock (_lock) {
        try {
            var json = File.ReadAllText(path, Encoding.UTF8);
            if (string.IsNullOrEmpty(json)) return EmptyDB();
            return JsonParse(json);
        } catch { return EmptyDB(); }
    }
}

void WriteDB(Dictionary<string, object> db) {
    var path = DataPath();
    var dir = System.IO.Path.GetDirectoryName(path);
    if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
    lock (_lock) {
        var tmp = path + ".tmp." + Guid.NewGuid().ToString("N").Substring(0, 8);
        var json = JsonStringify(db);
        File.WriteAllText(tmp, json, new UTF8Encoding(false));
        if (File.Exists(path)) File.Delete(path);
        File.Move(tmp, path);
    }
}

Dictionary<string, object> EmptyDB() {
    return new Dictionary<string, object> {
        { "surveys", new object[0] },
        { "questions", new object[0] },
        { "options", new object[0] },
        { "submissions", new object[0] },
        { "answers", new object[0] },
        { "admins", new object[0] }
    };
}

Dictionary<string, object> LoadConfig() {
    var path = ConfigPath();
    if (!File.Exists(path)) return new Dictionary<string, object>();
    try {
        var json = File.ReadAllText(path, Encoding.UTF8);
        if (string.IsNullOrEmpty(json)) return new Dictionary<string, object>();
        return JsonParse(json);
    } catch { return new Dictionary<string, object>(); }
}
string JsonStringify(object v) {
    if (v == null) return "null";
    if (v is string s) return "\"" + EscapeJson(s) + "\"";
    if (v is bool b) return b ? "true" : "false";
    if (v is int || v is long || v is double || v is decimal) return Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture);
    if (v is Dictionary<string, object> d) {
        var parts = new List<string>();
        foreach (var kv in d) parts.Add("\"" + EscapeJson(kv.Key) + "\":" + JsonStringify(kv.Value));
        return "{" + string.Join(",", parts) + "}";
    }
    if (v is object[] arr) {
        var parts = new List<string>();
        foreach (var item in arr) parts.Add(JsonStringify(item));
        return "[" + string.Join(",", parts) + "]";
    }
    return "\"" + EscapeJson(v.ToString()) + "\"";
}

string EscapeJson(string s) {
    if (string.IsNullOrEmpty(s)) return "";
    var sb = new StringBuilder();
    foreach (char c in s) {
        switch (c) {
            case '"': sb.Append("\\\""); break;
            case '\\': sb.Append("\\\\"); break;
            case '\b': sb.Append("\\b"); break;
            case '\f': sb.Append("\\f"); break;
            case '\n': sb.Append("\\n"); break;
            case '\r': sb.Append("\\r"); break;
            case '\t': sb.Append("\\t"); break;
            default:
                if (c < 32) sb.AppendFormat("\\u{0:x4}", (int)c);
                else sb.Append(c);
                break;
        }
    }
    return sb.ToString();
}

Dictionary<string, object> JsonParse(string json) {
    var p = new JsonParser(json);
    return p.Parse();
}

class JsonParser {
    string src; int pos; int len;
    public JsonParser(string s) { src = s; len = s.Length; pos = 0; SkipWS(); }
    public Dictionary<string, object> Parse() { var r = ParseValue(); return r is Dictionary<string, object> d ? d : new Dictionary<string, object>(); }
    void SkipWS() { while (pos < len && (src[pos] == ' ' || src[pos] == '\t' || src[pos] == '\n' || src[pos] == '\r')) pos++; }
    object ParseValue() {
        SkipWS(); if (pos >= len) return null;
        char c = src[pos];
        if (c == '{') return ParseObject();
        if (c == '[') return ParseArray();
        if (c == '"') return ParseString();
        if (c == 't' || c == 'f') { return ParseBool(); }
        if (c == 'n') { pos += 4; return null; }
        return ParseNumber();
    }
    Dictionary<string, object> ParseObject() {
        var d = new Dictionary<string, object>(); pos++;
        SkipWS(); if (pos < len && src[pos] == '}') { pos++; return d; }
        while (pos < len) {
            SkipWS(); var key = ParseString(); SkipWS();
            if (pos < len && src[pos] == ':') pos++; SkipWS();
            d[key] = ParseValue(); SkipWS();
            if (pos < len && src[pos] == '}') { pos++; return d; }
            if (pos < len && src[pos] == ',') pos++;
        }
        return d;
    }
    object[] ParseArray() {
        var list = new List<object>(); pos++;
        SkipWS(); if (pos < len && src[pos] == ']') { pos++; return list.ToArray(); }
        while (pos < len) {
            SkipWS(); list.Add(ParseValue()); SkipWS();
            if (pos < len && src[pos] == ']') { pos++; return list.ToArray(); }
            if (pos < len && src[pos] == ',') pos++;
        }
        return list.ToArray();
    }
    string ParseString() {
        pos++; var sb = new StringBuilder();
        while (pos < len) {
            char c = src[pos];
            if (c == '"') { pos++; return sb.ToString(); }
            if (c == '\\') {
                pos++; if (pos >= len) break;
                switch (src[pos]) {
                    case '"': sb.Append('"'); break; case '\\': sb.Append('\\'); break;
                    case '/': sb.Append('/'); break; case 'b': sb.Append('\b'); break;
                    case 'f': sb.Append('\f'); break; case 'n': sb.Append('\n'); break;
                    case 'r': sb.Append('\r'); break; case 't': sb.Append('\t'); break;
                    case 'u': if (pos + 4 < len) { sb.Append((char)Convert.ToInt32(src.Substring(pos + 1, 4), 16)); pos += 4; } break;
                }
            } else sb.Append(c);
            pos++;
        }
        return sb.ToString();
    }
    double ParseNumber() { int start = pos; while (pos < len && "0123456789.-+eE".IndexOf(src[pos]) >= 0) pos++; return double.Parse(src.Substring(start, pos - start), System.Globalization.CultureInfo.InvariantCulture); }
    bool ParseBool() { if (pos + 3 < len && src.Substring(pos, 4) == "true") { pos += 4; return true; } if (pos + 4 < len && src.Substring(pos, 5) == "false") { pos += 5; return false; } return false; }
}

void WriteOk(object data) { Response.Write("{\"ok\":true,\"data\":" + JsonStringify(data) + "}"); }
void WriteErr(string msg) { Response.Write("{\"ok\":false,\"message\":\"" + EscapeJson(msg) + "\"}"); }

string GetBody() {
    if (Request.TotalBytes > 1048576) return "";
    var bytes = new byte[Request.TotalBytes];
    Request.InputStream.Read(bytes, 0, bytes.Length);
    return Encoding.UTF8.GetString(bytes);
}

string SafeStr(Dictionary<string, object> d, string key, string def = "") { return d.ContainsKey(key) && d[key] is string s ? s : def; }
bool SafeBool(Dictionary<string, object> d, string key, bool def = false) { return d.ContainsKey(key) ? Convert.ToBoolean(d[key]) : def; }
int SafeInt(Dictionary<string, object> d, string key, int def = 0) { return d.ContainsKey(key) ? Convert.ToInt32(d[key]) : def; }
string NewUUID() { return Guid.NewGuid().ToString().ToLower(); }
string NowISO() { return DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss") + "+08:00"; }

void HandleMe() { WriteOk(new Dictionary<string, object>{ { "username", GetUsername() }, { "is_admin", IsAdmin(GetUsername()) } }); }
void HandleCheckAdmin() { WriteOk(new Dictionary<string, object>{ { "is_admin", IsAdmin(GetUsername()) } }); }

/* ===== 问卷访问端 ===== */

void HandleGetSurvey(string id) {
    var db = ReadDB();
    object[] surveys = (object[])db["surveys"];
    object[] questions = (object[])db["questions"];
    object[] options = (object[])db["options"];

    object found = null;
    foreach (var s in surveys) {
        var sd = (Dictionary<string, object>)s;
        if (Convert.ToString(sd["id"]) == id) { found = sd; break; }
    }
    if (found == null) { WriteErr("survey not found"); return; }

    // 只返回发布的问卷
    var sd2 = (Dictionary<string, object>)found;
    if (Convert.ToString(sd2["status"]) != "published") { WriteErr("survey not found"); return; }

    var qlist = new List<object>();
    foreach (var q in questions) {
        var qd = (Dictionary<string, object>)q;
        if (Convert.ToString(qd["survey_id"]) != id) continue;
        var olist = new List<object>();
        foreach (var o in options) {
            var od = (Dictionary<string, object>)o;
            if (Convert.ToString(od["question_id"]) == Convert.ToString(qd["id"]))
                olist.Add(od);
        }
        qd["options"] = olist.ToArray();
        qlist.Add(qd);
    }
    sd2["questions"] = qlist.ToArray();
    WriteOk(sd2);
}

void HandleCheckSubmitted(string id) {
    var username = GetUsername();
    if (string.IsNullOrEmpty(username)) { WriteOk(new Dictionary<string, object>{ { "submitted", false } }); return; }
    var db = ReadDB();
    object[] submissions = (object[])db["submissions"];
    bool found = false;
    foreach (var sub in submissions) {
        var sd = (Dictionary<string, object>)sub;
        if (Convert.ToString(sd["survey_id"]) == id && string.Equals(Convert.ToString(sd["username"]), username, StringComparison.OrdinalIgnoreCase)) {
            found = true; break;
        }
    }
    WriteOk(new Dictionary<string, object>{ { "submitted", found } });
}

void HandleSubmitSurvey(string id) {
    var username = GetUsername();
    if (string.IsNullOrEmpty(username)) { WriteErr("auth required"); return; }

    var body = GetBody();
    if (string.IsNullOrEmpty(body)) { WriteErr("empty body"); return; }
    var input = JsonParse(body);

    // 验证问卷存在且已发布
    var db = ReadDB();
    object[] surveys = (object[])db["surveys"];
    object found = null;
    foreach (var s in surveys) {
        var sd = (Dictionary<string, object>)s;
        if (Convert.ToString(sd["id"]) == id) { found = sd; break; }
    }
    if (found == null) { WriteErr("survey not found"); return; }
    var srv = (Dictionary<string, object>)found;
    if (Convert.ToString(srv["status"]) != "published") { WriteErr("survey not published"); return; }

    // 检查是否已经提交过
    object[] submissions = (object[])db["submissions"];
    foreach (var sub in submissions) {
        var sd = (Dictionary<string, object>)sub;
        if (Convert.ToString(sd["survey_id"]) == id && string.Equals(Convert.ToString(sd["username"]), username, StringComparison.OrdinalIgnoreCase)) {
            WriteErr("already submitted"); return;
        }
    }

    var answers = input.ContainsKey("answers") ? (object[])input["answers"] : new object[0];
    var subId = NewUUID();
    var subEntry = new Dictionary<string, object> {
        { "id", subId },
        { "survey_id", id },
        { "username", username },
        { "submitted_at", NowISO() }
    };
    var list = (List<object>)new List<object>(submissions) { subEntry };
    db["submissions"] = list.ToArray();

    var ansList = new List<object>();
    foreach (var a in answers) {
        var ad = (Dictionary<string, object>)a;
        ansList.Add(new Dictionary<string, object> {
            { "id", NewUUID() },
            { "submission_id", subId },
            { "question_id", SafeStr(ad, "question_id") },
            { "value", ad.ContainsKey("value") ? ad["value"] : "" }
        });
    }
    var allAnswers = new List<object>((object[])db["answers"]);
    allAnswers.AddRange(ansList);
    db["answers"] = allAnswers.ToArray();
    WriteDB(db);
    WriteOk(new Dictionary<string, object>{ { "submission_id", subId } });
}

void HandleGetStats(string id) {
    var db = ReadDB();
    object[] surveys = (object[])db["surveys"];
    object[] questions = (object[])db["questions"];
    object[] options = (object[])db["options"];
    object[] submissions = (object[])db["submissions"];
    object[] answers = (object[])db["answers"];

    object found = null;
    foreach (var s in surveys) {
        var sd = (Dictionary<string, object>)s;
        if (Convert.ToString(sd["id"]) == id) { found = sd; break; }
    }
    if (found == null) { WriteErr("survey not found"); return; }

    int total = 0;
    foreach (var sub in submissions) {
        if (Convert.ToString(((Dictionary<string, object>)sub)["survey_id"]) == id) total++;
    }

    var qlist = new List<object>();
    foreach (var q in questions) {
        var qd = (Dictionary<string, object>)q;
        if (Convert.ToString(qd["survey_id"]) != id) continue;
        var olist = new List<object>();
        foreach (var o in options) {
            var od = (Dictionary<string, object>)o;
            if (Convert.ToString(od["question_id"]) == Convert.ToString(qd["id"]))
                olist.Add(new Dictionary<string, object> {
                    { "id", SafeStr(od, "id") },
                    { "content", SafeStr(od, "content") },
                    { "count", 0 }
                });
        }

        // 统计每个选项的计数
        if (olist.Count > 0) {
            foreach (var a in answers) {
                var ad = (Dictionary<string, object>)a;
                if (Convert.ToString(ad["question_id"]) != Convert.ToString(qd["id"])) continue;
                // 确认该回答属于此问卷的提交
                string subId = Convert.ToString(ad["submission_id"]);
                bool belongs = false;
                foreach (var sub in submissions) {
                    var sd2 = (Dictionary<string, object>)sub;
                    if (Convert.ToString(sd2["id"]) == subId && Convert.ToString(sd2["survey_id"]) == id) {
                        belongs = true; break;
                    }
                }
                if (!belongs) continue;

                string val = Convert.ToString(ad["value"]);
                foreach (var o in olist) {
                    var od = (Dictionary<string, object>)o;
                    if (Convert.ToString(od["id"]) == val) {
                        od["count"] = Convert.ToInt32(od["count"]) + 1;
                        break;
                    }
                }
            }
        }

        qlist.Add(new Dictionary<string, object> {
            { "id", SafeStr(qd, "id") },
            { "title", SafeStr(qd, "title") },
            { "type", SafeStr(qd, "type") },
            { "options", olist.ToArray() }
        });
    }
    WriteOk(new Dictionary<string, object>{ { "total", total }, { "questions", qlist.ToArray() } });
}
/* ===== 管理端 - 问卷CRUD ===== */

void HandleListAdminSurveys() {
    var db = ReadDB();
    object[] surveys = (object[])db["surveys"];
    object[] questions = (object[])db["questions"];

    var list = new List<object>();
    foreach (var s in surveys) {
        var sd = (Dictionary<string, object>)s;
        int qcount = 0;
        foreach (var q in questions) {
            if (Convert.ToString(((Dictionary<string, object>)q)["survey_id"]) == Convert.ToString(sd["id"]))
                qcount++;
        }
        var copy = new Dictionary<string, object>();
        foreach (var kv in sd) copy[kv.Key] = kv.Value;
        copy["question_count"] = qcount;
        list.Add(copy);
    }
    WriteOk(list.ToArray());
}

void HandleCreateAdminSurvey() {
    var body = GetBody();
    if (string.IsNullOrEmpty(body)) { WriteErr("empty body"); return; }
    var input = JsonParse(body);
    var now = NowISO();
    var entry = new Dictionary<string, object> {
        { "id", NewUUID() },
        { "title", SafeStr(input, "title", "未命名问卷") },
        { "description", SafeStr(input, "description") },
        { "status", "draft" },
        { "is_anonymous", SafeBool(input, "is_anonymous") },
        { "deadline", SafeStr(input, "deadline") },
        { "created_at", now },
        { "updated_at", now }
    };
    var db = ReadDB();
    var list = new List<object>((object[])db["surveys"]) { entry };
    db["surveys"] = list.ToArray();
    WriteDB(db);
    WriteOk(entry);
}

void HandleUpdateAdminSurvey(string id) {
    var body = GetBody();
    if (string.IsNullOrEmpty(body)) { WriteErr("empty body"); return; }
    var input = JsonParse(body);
    var db = ReadDB();
    object[] surveys = (object[])db["surveys"];
    bool found = false;
    for (int i = 0; i < surveys.Length; i++) {
        var sd = (Dictionary<string, object>)surveys[i];
        if (Convert.ToString(sd["id"]) == id) {
            if (input.ContainsKey("title")) sd["title"] = SafeStr(input, "title");
            if (input.ContainsKey("description")) sd["description"] = SafeStr(input, "description");
            if (input.ContainsKey("is_anonymous")) sd["is_anonymous"] = SafeBool(input, "is_anonymous");
            if (input.ContainsKey("deadline")) sd["deadline"] = SafeStr(input, "deadline");
            sd["updated_at"] = NowISO();
            surveys[i] = sd;
            found = true;
            break;
        }
    }
    if (!found) { WriteErr("survey not found"); return; }
    db["surveys"] = surveys;
    WriteDB(db);
    WriteOk("updated");
}

void HandleDeleteAdminSurvey(string id) {
    var db = ReadDB();
    object[] surveys = (object[])db["surveys"];
    var list = new List<object>();
    bool found = false;
    foreach (var s in surveys) {
        var sd = (Dictionary<string, object>)s;
        if (Convert.ToString(sd["id"]) == id) { found = true; continue; }
        list.Add(s);
    }
    if (!found) { WriteErr("survey not found"); return; }
    db["surveys"] = list.ToArray();

    // 删除关联的问题、选项、提交、回答
    var qlist = new List<object>();
    foreach (var q in (object[])db["questions"]) {
        if (Convert.ToString(((Dictionary<string, object>)q)["survey_id"]) != id)
            qlist.Add(q);
    }
    db["questions"] = qlist.ToArray();

    var olist = new List<object>();
    foreach (var o in (object[])db["options"]) {
        qlist.Clear();
        foreach (var q in (object[])db["questions"]) {
            if (Convert.ToString(((Dictionary<string, object>)q)["id"]) == Convert.ToString(((Dictionary<string, object>)o)["question_id"]))
                qlist.Add(q);
        }
        if (qlist.Count > 0) olist.Add(o);
    }
    // 简化的选项清理
    var keptOptions = new List<object>();
    var keptQuestionIds = new HashSet<string>();
    foreach (var q in (object[])db["questions"]) {
        keptQuestionIds.Add(Convert.ToString(((Dictionary<string, object>)q)["id"]));
    }
    foreach (var o in (object[])db["options"]) {
        if (keptQuestionIds.Contains(Convert.ToString(((Dictionary<string, object>)o)["question_id"])))
            keptOptions.Add(o);
    }
    db["options"] = keptOptions.ToArray();

    var keptSubmissions = new List<object>();
    foreach (var sub in (object[])db["submissions"]) {
        if (Convert.ToString(((Dictionary<string, object>)sub)["survey_id"]) != id)
            keptSubmissions.Add(sub);
    }
    db["submissions"] = keptSubmissions.ToArray();

    var keptAnswers = new List<object>();
    var keptSubIds = new HashSet<string>();
    foreach (var sub in keptSubmissions) {
        keptSubIds.Add(Convert.ToString(((Dictionary<string, object>)sub)["id"]));
    }
    foreach (var a in (object[])db["answers"]) {
        if (keptSubIds.Contains(Convert.ToString(((Dictionary<string, object>)a)["submission_id"])))
            keptAnswers.Add(a);
    }
    db["answers"] = keptAnswers.ToArray();

    WriteDB(db);
    WriteOk("deleted");
}

void HandleUpdateSurveyStatus(string id) {
    var body = GetBody();
    if (string.IsNullOrEmpty(body)) { WriteErr("empty body"); return; }
    var input = JsonParse(body);
    var status = SafeStr(input, "status", "draft");
    var db = ReadDB();
    object[] surveys = (object[])db["surveys"];
    bool found = false;
    for (int i = 0; i < surveys.Length; i++) {
        var sd = (Dictionary<string, object>)surveys[i];
        if (Convert.ToString(sd["id"]) == id) {
            sd["status"] = status;
            sd["updated_at"] = NowISO();
            surveys[i] = sd;
            found = true; break;
        }
    }
    if (!found) { WriteErr("survey not found"); return; }
    db["surveys"] = surveys;
    WriteDB(db);
    WriteOk("updated");
}

/* ===== 管理端 - 问题CRUD ===== */

void HandleCreateQuestion(string surveyId) {
    var body = GetBody();
    if (string.IsNullOrEmpty(body)) { WriteErr("empty body"); return; }
    var input = JsonParse(body);
    var db = ReadDB();

    // 计算 sort_order
    object[] questions = (object[])db["questions"];
    int maxOrder = 0;
    foreach (var q in questions) {
        var qd = (Dictionary<string, object>)q;
        if (Convert.ToString(qd["survey_id"]) == surveyId) {
            int o = SafeInt(qd, "sort_order");
            if (o > maxOrder) maxOrder = o;
        }
    }

    var qid = NewUUID();
    var entry = new Dictionary<string, object> {
        { "id", qid },
        { "survey_id", surveyId },
        { "title", SafeStr(input, "title", "新问题") },
        { "type", SafeStr(input, "type", "single") },
        { "required", SafeBool(input, "required", true) },
        { "char_limit", SafeInt(input, "char_limit") },
        { "sort_order", maxOrder + 1 }
    };
    var list = new List<object>(questions) { entry };
    db["questions"] = list.ToArray();

    // 创建选项（如果是 single/multi 类型）
    if (input.ContainsKey("options") && input["options"] is object[] optArr) {
        var olist = new List<object>((object[])db["options"]);
        foreach (var o in optArr) {
            var od = (Dictionary<string, object>)o;
            olist.Add(new Dictionary<string, object> {
                { "id", NewUUID() },
                { "question_id", qid },
                { "content", SafeStr(od, "content") },
                { "sort_order", SafeInt(od, "sort_order", olist.Count) }
            });
        }
        db["options"] = olist.ToArray();
    }

    WriteDB(db);
    WriteOk(entry);
}

void HandleUpdateQuestion(string surveyId, string qid) {
    var body = GetBody();
    if (string.IsNullOrEmpty(body)) { WriteErr("empty body"); return; }
    var input = JsonParse(body);
    var db = ReadDB();
    object[] questions = (object[])db["questions"];
    bool found = false;
    for (int i = 0; i < questions.Length; i++) {
        var qd = (Dictionary<string, object>)questions[i];
        if (Convert.ToString(qd["id"]) == qid && Convert.ToString(qd["survey_id"]) == surveyId) {
            if (input.ContainsKey("title")) qd["title"] = SafeStr(input, "title");
            if (input.ContainsKey("type")) qd["type"] = SafeStr(input, "type");
            if (input.ContainsKey("required")) qd["required"] = SafeBool(input, "required");
            if (input.ContainsKey("char_limit")) qd["char_limit"] = SafeInt(input, "char_limit");
            if (input.ContainsKey("sort_order")) qd["sort_order"] = SafeInt(input, "sort_order");
            questions[i] = qd;
            found = true; break;
        }
    }
    if (!found) { WriteErr("question not found"); return; }
    db["questions"] = questions;

    // 更新选项
    if (input.ContainsKey("options") && input["options"] is object[] optArr) {
        var olist = new List<object>();
        // 保留未修改的选项
        foreach (var o in (object[])db["options"]) {
            var od = (Dictionary<string, object>)o;
            if (Convert.ToString(od["question_id"]) != qid)
                olist.Add(o);
        }
        // 添加新选项
        foreach (var o in optArr) {
            var od = (Dictionary<string, object>)o;
            olist.Add(new Dictionary<string, object> {
                { "id", SafeStr(od, "id", NewUUID()) },
                { "question_id", qid },
                { "content", SafeStr(od, "content") },
                { "sort_order", SafeInt(od, "sort_order", olist.Count) }
            });
        }
        db["options"] = olist.ToArray();
    }

    WriteDB(db);
    WriteOk("updated");
}

void HandleDeleteQuestion(string surveyId, string qid) {
    var db = ReadDB();
    object[] questions = (object[])db["questions"];
    var list = new List<object>();
    bool found = false;
    foreach (var q in questions) {
        var qd = (Dictionary<string, object>)q;
        if (Convert.ToString(qd["id"]) == qid && Convert.ToString(qd["survey_id"]) == surveyId) {
            found = true; continue;
        }
        list.Add(q);
    }
    if (!found) { WriteErr("question not found"); return; }
    db["questions"] = list.ToArray();

    // 删除关联的选项
    var olist = new List<object>();
    foreach (var o in (object[])db["options"]) {
        if (Convert.ToString(((Dictionary<string, object>)o)["question_id"]) != qid)
            olist.Add(o);
    }
    db["options"] = olist.ToArray();

    WriteDB(db);
    WriteOk("deleted");
}

void HandleReorderQuestions(string surveyId) {
    var body = GetBody();
    if (string.IsNullOrEmpty(body)) { WriteErr("empty body"); return; }
    var input = JsonParse(body);
    if (!(input.ContainsKey("ids") && input["ids"] is object[] idsArr)) {
        WriteErr("ids required"); return;
    }
    var db = ReadDB();
    object[] questions = (object[])db["questions"];
    var order = new Dictionary<string, int>();
    for (int i = 0; i < idsArr.Length; i++) {
        order[Convert.ToString(idsArr[i])] = i;
    }
    for (int i = 0; i < questions.Length; i++) {
        var qd = (Dictionary<string, object>)questions[i];
        if (order.ContainsKey(Convert.ToString(qd["id"])))
            qd["sort_order"] = order[Convert.ToString(qd["id"])];
        questions[i] = qd;
    }
    db["questions"] = questions;
    WriteDB(db);
    WriteOk("reordered");
}
/* ===== 管理端 - 提交记录 & 导出 ===== */

void HandleListSubmissions(string surveyId) {
    var db = ReadDB();
    object[] submissions = (object[])db["submissions"];
    object[] answers = (object[])db["answers"];
    object[] questions = (object[])db["questions"];

    var subList = new List<object>();
    foreach (var sub in submissions) {
        var sd = (Dictionary<string, object>)sub;
        if (Convert.ToString(sd["survey_id"]) != surveyId) continue;
        var ansList = new List<object>();
        foreach (var a in answers) {
            var ad = (Dictionary<string, object>)a;
            if (Convert.ToString(ad["submission_id"]) == Convert.ToString(sd["id"])) {
                // 找到对应的问题标题
                string qTitle = "";
                foreach (var q in questions) {
                    var qd = (Dictionary<string, object>)q;
                    if (Convert.ToString(qd["id"]) == Convert.ToString(ad["question_id"])) {
                        qTitle = SafeStr(qd, "title"); break;
                    }
                }
                ansList.Add(new Dictionary<string, object> {
                    { "question_id", SafeStr(ad, "question_id") },
                    { "question_title", qTitle },
                    { "value", ad["value"] }
                });
            }
        }
        subList.Add(new Dictionary<string, object> {
            { "id", SafeStr(sd, "id") },
            { "username", SafeStr(sd, "username") },
            { "submitted_at", SafeStr(sd, "submitted_at") },
            { "answers", ansList.ToArray() }
        });
    }
    WriteOk(subList.ToArray());
}

void HandleExportCSV(string surveyId) {
    var db = ReadDB();
    object[] surveys = (object[])db["surveys"];
    object[] questions = (object[])db["questions"];
    object[] submissions = (object[])db["submissions"];
    object[] answers = (object[])db["answers"];

    string title = "";
    foreach (var s in surveys) {
        var sd = (Dictionary<string, object>)s;
        if (Convert.ToString(sd["id"]) == surveyId) { title = SafeStr(sd, "title"); break; }
    }

    // 收集问题列
    var qcols = new List<Dictionary<string, object>>();
    foreach (var q in questions) {
        var qd = (Dictionary<string, object>)q;
        if (Convert.ToString(qd["survey_id"]) == surveyId)
            qcols.Add(qd);
    }

    var sb = new StringBuilder();
    // CSV header
    sb.Append("提交时间,用户名");
    foreach (var q in qcols) {
        var qTitle = SafeStr(q, "title").Replace("\"", "\"\"");
        sb.Append(",\"").Append(qTitle).Append("\"");
    }
    sb.AppendLine();

    foreach (var sub in submissions) {
        var sd = (Dictionary<string, object>)sub;
        if (Convert.ToString(sd["survey_id"]) != surveyId) continue;

        // 构建回答字典
        var ansMap = new Dictionary<string, object>();
        foreach (var a in answers) {
            var ad = (Dictionary<string, object>)a;
            if (Convert.ToString(ad["submission_id"]) == Convert.ToString(sd["id"]))
                ansMap[Convert.ToString(ad["question_id"])] = ad["value"];
        }

        var subTime = SafeStr(sd, "submitted_at");
        var username = SafeStr(sd, "username");
        sb.Append(subTime).Append(",").Append(username);

        foreach (var q in qcols) {
            sb.Append(",");
            var qid = SafeStr(q, "id");
            if (ansMap.ContainsKey(qid)) {
                var val = Convert.ToString(ansMap[qid]);
                if (val.Contains(",") || val.Contains("\"") || val.Contains("\n"))
                    sb.Append("\"").Append(val.Replace("\"", "\"\"")).Append("\"");
                else
                    sb.Append(val);
            }
        }
        sb.AppendLine();
    }

    Response.Clear();
    Response.ContentType = "text/csv; charset=utf-8";
    Response.AddHeader("Content-Disposition", "attachment; filename=\"" + title.Replace("\"", "") + ".csv\"");
    // BOM for Excel
    Response.Write("\xEF\xBB\xBF");
    Response.Write(sb.ToString());
    Response.End();
}

/* ===== 管理端 - 管理员用户管理 ===== */

void HandleListAdmins() {
    var db = ReadDB();
    object[] admins = (object[])db["admins"];
    WriteOk(admins);
}

void HandleAddAdmin() {
    var body = GetBody();
    if (string.IsNullOrEmpty(body)) { WriteErr("empty body"); return; }
    var input = JsonParse(body);
    var username = SafeStr(input, "username");
    if (string.IsNullOrEmpty(username)) { WriteErr("username required"); return; }
    if (username.Contains("\\")) username = username.Substring(username.IndexOf('\\') + 1);
    username = username.ToLower();

    var db = ReadDB();
    object[] admins = (object[])db["admins"];
    // 检查是否已存在
    foreach (var a in admins) {
        var ad = (Dictionary<string, object>)a;
        if (string.Equals(SafeStr(ad, "username"), username, StringComparison.OrdinalIgnoreCase)) {
            WriteErr("already admin"); return;
        }
    }
    var list = new List<object>(admins) {
        new Dictionary<string, object> {
            { "id", NewUUID() },
            { "username", username },
            { "created_at", NowISO() }
        }
    };
    db["admins"] = list.ToArray();
    WriteDB(db);
    WriteOk("added");
}

void HandleRemoveAdmin(string id) {
    var db = ReadDB();
    object[] admins = (object[])db["admins"];
    var list = new List<object>();
    bool found = false;
    foreach (var a in admins) {
        var ad = (Dictionary<string, object>)a;
        if (Convert.ToString(ad["id"]) == id) { found = true; continue; }
        list.Add(a);
    }
    if (!found) { WriteErr("admin not found"); return; }
    db["admins"] = list.ToArray();
    WriteDB(db);
    WriteOk("removed");
}

</script>
