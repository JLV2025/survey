<%@ WebHandler Language="C#" Class="SurveyApi" %>
using System;
using System.IO;
using System.Text;
using System.Web;
using System.Collections.Generic;

public class SurveyApi : IHttpHandler {
    public bool IsReusable { get { return false; } }

    public void ProcessRequest(HttpContext ctx) {
        try {
            ctx.Response.ContentType = "application/json";
            ctx.Response.Charset = "UTF-8";
            var path = ctx.Request.QueryString["path"] ?? "";
            Route(ctx, ctx.Request.HttpMethod.ToUpperInvariant(), path);
        } catch (Exception ex) {
            ctx.Response.Write("{\"ok\":false,\"message\":\"error: " + ex.Message + "\"}");
        }
    }

    void Route(HttpContext ctx, string method, string path) {
        var seg = path.Split(new char[] { '/' }, StringSplitOptions.RemoveEmptyEntries);
        var n = seg.Length;

        if (method == "GET" && path == "health") { WriteOk(ctx, "OK"); return; }
        if (method == "GET" && path == "me") { HandleMe(ctx); return; }
        if (method == "GET" && path == "check-admin") { HandleCheckAdmin(ctx); return; }
        if (method == "GET" && n == 2 && seg[0] == "surveys") { HandleGetSurvey(ctx, seg[1]); return; }
        if (method == "GET" && n == 3 && seg[0] == "surveys" && seg[2] == "check") { HandleCheckSubmitted(ctx, seg[1]); return; }
        if (method == "POST" && n == 3 && seg[0] == "surveys" && seg[2] == "submit") { HandleSubmitSurvey(ctx, seg[1]); return; }
        if (method == "GET" && n == 3 && seg[0] == "surveys" && seg[2] == "stats") { HandleGetStats(ctx, seg[1]); return; }
        if (n > 0 && seg[0] == "admin") {
            if (!RequireAdmin(ctx)) return;
            if (method == "GET" && n == 2 && seg[1] == "surveys") { HandleListAdminSurveys(ctx); return; }
            if (method == "POST" && n == 2 && seg[1] == "surveys") { HandleCreateAdminSurvey(ctx); return; }
            if (method == "PUT" && n == 3 && seg[1] == "surveys") { HandleUpdateAdminSurvey(ctx, seg[2]); return; }
            if (method == "DELETE" && n == 3 && seg[1] == "surveys") { HandleDeleteAdminSurvey(ctx, seg[2]); return; }
            if (method == "PUT" && n == 4 && seg[1] == "surveys" && seg[3] == "status") { HandleUpdateSurveyStatus(ctx, seg[2]); return; }
            if (method == "POST" && n == 4 && seg[1] == "surveys" && seg[3] == "questions") { HandleCreateQuestion(ctx, seg[2]); return; }
            if (method == "PUT" && n == 5 && seg[1] == "surveys" && seg[3] == "questions") { HandleUpdateQuestion(ctx, seg[2], seg[4]); return; }
            if (method == "DELETE" && n == 5 && seg[1] == "surveys" && seg[3] == "questions") { HandleDeleteQuestion(ctx, seg[2], seg[4]); return; }
            if (method == "PUT" && n == 5 && seg[1] == "surveys" && seg[3] == "questions" && seg[4] == "reorder") { HandleReorderQuestions(ctx, seg[2]); return; }
            if (method == "GET" && n == 4 && seg[1] == "surveys" && seg[3] == "submissions") { HandleListSubmissions(ctx, seg[2]); return; }
            if (method == "GET" && n == 4 && seg[1] == "surveys" && seg[3] == "export") { HandleExportCSV(ctx, seg[2]); return; }
            if (method == "GET" && n == 2 && seg[1] == "users") { HandleListAdmins(ctx); return; }
            if (method == "POST" && n == 2 && seg[1] == "users") { HandleAddAdmin(ctx); return; }
            if (method == "DELETE" && n == 3 && seg[1] == "users") { HandleRemoveAdmin(ctx, seg[2]); return; }
            WriteErr(ctx, "route not found"); return;
    }
        WriteErr(ctx, "route not found");
    }

    // ===== Auth =====
    string GetUsername(HttpContext ctx) {
        var u = ctx.Request.ServerVariables["LOGON_USER"];
        if (string.IsNullOrEmpty(u)) u = ctx.Request.ServerVariables["AUTH_USER"];
        if (string.IsNullOrEmpty(u)) u = ctx.Request.ServerVariables["REMOTE_USER"];
        if (!string.IsNullOrEmpty(u) && u.Contains("\\")) u = u.Substring(u.IndexOf('\\') + 1);
        return (u ?? "").ToLower();
    }

    bool IsAdmin(HttpContext ctx, string username) {
        if (string.IsNullOrEmpty(username)) return false;
        var db = ReadDB();
        var admins = db.ContainsKey("admins") ? (object[])db["admins"] : new object[0];
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

    bool RequireAdmin(HttpContext ctx) {
        var u = GetUsername(ctx);
        if (string.IsNullOrEmpty(u)) { WriteErr(ctx, "auth failed: no user identity"); return false; }
        if (!IsAdmin(ctx, u)) { WriteErr(ctx, "no admin permission"); return false; }
        return true;
    }

    // ===== Storage =====
    string DataPath() { return System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "data", "survey.json"); }
    string ConfigPath() { return System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "config.json"); }
    static object _lock = new object();

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

    // ===== JSON (C# 5 compatible) =====
    string JsonStringify(object v) {
        if (v == null) return "null";
        if (v is string) return "\"" + EscapeJson((string)v) + "\"";
        if (v is bool) return ((bool)v) ? "true" : "false";
        if (v is int || v is long || v is double || v is decimal)
            return Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture);
        var _d = v as Dictionary<string, object>;
        if (_d != null) {
            var parts = new List<string>();
            foreach (var kv in _d) parts.Add("\"" + EscapeJson(kv.Key) + "\":" + JsonStringify(kv.Value));
            return "{" + string.Join(",", parts) + "}";
        }
        var _arr = v as object[];
        if (_arr != null) {
            var parts = new List<string>();
            foreach (var item in _arr) parts.Add(JsonStringify(item));
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
                    else sb.Append(c); break;
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
        public Dictionary<string, object> Parse() {
            var r = ParseValue() as Dictionary<string, object>;
            return r != null ? r : new Dictionary<string, object>();
        }
        void SkipWS() { while (pos < len && (src[pos] == ' ' || src[pos] == '\t' || src[pos] == '\n' || src[pos] == '\r')) pos++; }
        object ParseValue() {
            SkipWS(); if (pos >= len) return null;
            char c = src[pos];
            if (c == '{') return ParseObject();
            if (c == '[') return ParseArray();
            if (c == '"') return ParseString();
            if (c == 't' || c == 'f') return ParseBool();
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

    void WriteOk(HttpContext ctx, object data) { ctx.Response.Write("{\"ok\":true,\"data\":" + JsonStringify(data) + "}"); }
    void WriteErr(HttpContext ctx, string msg) { ctx.Response.Write("{\"ok\":false,\"message\":\"" + EscapeJson(msg) + "\"}"); }

    string GetBody(HttpContext ctx) {
        if (ctx.Request.TotalBytes > 1048576) return "";
        var bytes = new byte[ctx.Request.TotalBytes];
        ctx.Request.InputStream.Read(bytes, 0, bytes.Length);
        return Encoding.UTF8.GetString(bytes);
    }

    int SafeInt(Dictionary<string, object> d, string key) { object _v; return d.TryGetValue(key, out _v) ? Convert.ToInt32(_v) : 0; }
    string SafeStr(Dictionary<string, object> d, string key, string def) {
        object val;
        return d.TryGetValue(key, out val) ? Convert.ToString(val) : def;
    }

    string NewUUID() { return Guid.NewGuid().ToString().ToLower(); }
    string NowISO() { return DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss") + "+08:00"; }

    // ===== Handlers =====
    void HandleMe(HttpContext ctx) {
        WriteOk(ctx, new Dictionary<string, object>{
            { "username", GetUsername(ctx) },
            { "is_admin", IsAdmin(ctx, GetUsername(ctx)) }
        });
    }

    void HandleCheckAdmin(HttpContext ctx) {
        WriteOk(ctx, new Dictionary<string, object>{ { "is_admin", IsAdmin(ctx, GetUsername(ctx)) } });
    }

    void HandleGetSurvey(HttpContext ctx, string id) {
        var db = ReadDB();
        object[] surveys = (object[])db["surveys"];
        object[] questions = (object[])db["questions"];
        object[] options = (object[])db["options"];
        object found = null;
        foreach (var s in surveys) {
            var sd = (Dictionary<string, object>)s;
            if (Convert.ToString(sd["id"]) == id) { found = sd; break; }
        }
        if (found == null) { WriteErr(ctx, "survey not found"); return; }
        var sd2 = (Dictionary<string, object>)found;
        if (Convert.ToString(sd2["status"]) != "published") { WriteErr(ctx, "survey not found"); return; }
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
        WriteOk(ctx, sd2);
    }

    void HandleCheckSubmitted(HttpContext ctx, string id) {
        var username = GetUsername(ctx);
        if (string.IsNullOrEmpty(username)) { WriteOk(ctx, new Dictionary<string, object>{ { "submitted", false } }); return; }
        var db = ReadDB();
        object[] submissions = (object[])db["submissions"];
        bool found = false;
        foreach (var sub in submissions) {
            var sd = (Dictionary<string, object>)sub;
            if (Convert.ToString(sd["survey_id"]) == id && string.Equals(Convert.ToString(sd["username"]), username, StringComparison.OrdinalIgnoreCase)) {
                found = true; break;
            }
        }
        WriteOk(ctx, new Dictionary<string, object>{ { "submitted", found } });
    }

    void HandleSubmitSurvey(HttpContext ctx, string id) {
        var username = GetUsername(ctx);
        if (string.IsNullOrEmpty(username)) { WriteErr(ctx, "auth required"); return; }
        var body = GetBody(ctx);
        if (string.IsNullOrEmpty(body)) { WriteErr(ctx, "empty body"); return; }
        var input = JsonParse(body);
        var db = ReadDB();
        object[] surveys = (object[])db["surveys"];
        object found = null;
        foreach (var s in surveys) {
            var sd = (Dictionary<string, object>)s;
            if (Convert.ToString(sd["id"]) == id) { found = sd; break; }
        }
        if (found == null) { WriteErr(ctx, "survey not found"); return; }
        var srv = (Dictionary<string, object>)found;
        if (Convert.ToString(srv["status"]) != "published") { WriteErr(ctx, "survey not published"); return; }

        object[] submissions = (object[])db["submissions"];
        foreach (var sub in submissions) {
            var sd = (Dictionary<string, object>)sub;
            if (Convert.ToString(sd["survey_id"]) == id && string.Equals(Convert.ToString(sd["username"]), username, StringComparison.OrdinalIgnoreCase)) {
                WriteErr(ctx, "already submitted"); return;
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
        var list = new List<object>(submissions) { subEntry };
        db["submissions"] = list.ToArray();

        var ansList = new List<object>();
        foreach (var a in answers) {
            var ad = (Dictionary<string, object>)a;
            ansList.Add(new Dictionary<string, object> {
                { "id", NewUUID() },
                { "submission_id", subId },
                { "question_id", SafeStr(ad, "question_id", "") },
                { "value", ad.ContainsKey("value") ? ad["value"] : "" }
            });
        }
        var allAnswers = new List<object>((object[])db["answers"]);
        allAnswers.AddRange(ansList);
        db["answers"] = allAnswers.ToArray();
        WriteDB(db);
        WriteOk(ctx, new Dictionary<string, object>{ { "submission_id", subId } });
    }

    void HandleGetStats(HttpContext ctx, string id) {
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
        if (found == null) { WriteErr(ctx, "survey not found"); return; }
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
                        { "id", SafeStr(od, "id", "") },
                        { "content", SafeStr(od, "content", "") },
                        { "count", 0 }
                    });
            }
            if (olist.Count > 0) {
                foreach (var a in answers) {
                    var ad = (Dictionary<string, object>)a;
                    if (Convert.ToString(ad["question_id"]) != Convert.ToString(qd["id"])) continue;
                    string subIdStr = Convert.ToString(ad["submission_id"]);
                    bool belongs = false;
                    foreach (var sub in submissions) {
                        var sd2 = (Dictionary<string, object>)sub;
                        if (Convert.ToString(sd2["id"]) == subIdStr && Convert.ToString(sd2["survey_id"]) == id) {
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
                { "id", SafeStr(qd, "id", "") },
                { "title", SafeStr(qd, "title", "") },
                { "type", SafeStr(qd, "type", "") },
                { "options", olist.ToArray() }
            });
        }
        WriteOk(ctx, new Dictionary<string, object>{ { "total", total }, { "questions", qlist.ToArray() } });
    }
    // ===== Admin - Survey CRUD =====
    void HandleListAdminSurveys(HttpContext ctx) {
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
        WriteOk(ctx, list.ToArray());
    }

    void HandleCreateAdminSurvey(HttpContext ctx) {
        var body = GetBody(ctx);
        if (string.IsNullOrEmpty(body)) { WriteErr(ctx, "empty body"); return; }
        var input = JsonParse(body);
        var now = NowISO();
        var entry = new Dictionary<string, object> {
            { "id", NewUUID() },
            { "title", SafeStr(input, "title", "Untitled Survey") },
            { "description", SafeStr(input, "description", "") },
            { "status", "draft" },
            { "is_anonymous", false },
            { "deadline", SafeStr(input, "deadline", "") },
            { "created_at", now },
            { "updated_at", now }
        };
        var db = ReadDB();
        var list = new List<object>((object[])db["surveys"]) { entry };
        db["surveys"] = list.ToArray();
        WriteDB(db);
        WriteOk(ctx, entry);
    }

    void HandleUpdateAdminSurvey(HttpContext ctx, string id) {
        var body = GetBody(ctx);
        if (string.IsNullOrEmpty(body)) { WriteErr(ctx, "empty body"); return; }
        var input = JsonParse(body);
        var db = ReadDB();
        object[] surveys = (object[])db["surveys"];
        bool found = false;
        for (int i = 0; i < surveys.Length; i++) {
            var sd = (Dictionary<string, object>)surveys[i];
            if (Convert.ToString(sd["id"]) == id) {
                if (input.ContainsKey("title")) sd["title"] = SafeStr(input, "title", "");
                if (input.ContainsKey("description")) sd["description"] = SafeStr(input, "description", "");
                if (input.ContainsKey("deadline")) sd["deadline"] = SafeStr(input, "deadline", "");
                sd["updated_at"] = NowISO();
                surveys[i] = sd;
                found = true; break;
            }
        }
        if (!found) { WriteErr(ctx, "survey not found"); return; }
        db["surveys"] = surveys;
        WriteDB(db);
        WriteOk(ctx, "updated");
    }

    void HandleDeleteAdminSurvey(HttpContext ctx, string id) {
        var db = ReadDB();
        object[] surveys = (object[])db["surveys"];
        var list = new List<object>();
        bool found = false;
        foreach (var s in surveys) {
            var sd = (Dictionary<string, object>)s;
            if (Convert.ToString(sd["id"]) == id) { found = true; continue; }
            list.Add(s);
        }
        if (!found) { WriteErr(ctx, "survey not found"); return; }
        db["surveys"] = list.ToArray();

        var keptQ = new List<object>();
        foreach (var q in (object[])db["questions"]) {
            if (Convert.ToString(((Dictionary<string, object>)q)["survey_id"]) != id) keptQ.Add(q);
        }
        db["questions"] = keptQ.ToArray();
        Dictionary<string, bool> keptQIds = new Dictionary<string, bool>();
        foreach (var q in keptQ) keptQIds[Convert.ToString(((Dictionary<string, object>)q)["id"])] = true;
        var keptOpt = new List<object>();
        foreach (var o in (object[])db["options"]) {
            if (keptQIds.ContainsKey(Convert.ToString(((Dictionary<string, object>)o)["question_id"]))) keptOpt.Add(o);
        }
        db["options"] = keptOpt.ToArray();
        var keptSubs = new List<object>();
        foreach (var sub in (object[])db["submissions"]) {
            if (Convert.ToString(((Dictionary<string, object>)sub)["survey_id"]) != id) keptSubs.Add(sub);
        }
        db["submissions"] = keptSubs.ToArray();
        Dictionary<string, bool> keptSubIds = new Dictionary<string, bool>();
        foreach (var sub in keptSubs) keptSubIds[Convert.ToString(((Dictionary<string, object>)sub)["id"])] = true;
        var keptAns = new List<object>();
        foreach (var a in (object[])db["answers"]) {
            if (keptSubIds.ContainsKey(Convert.ToString(((Dictionary<string, object>)a)["submission_id"]))) keptAns.Add(a);
        }
        db["answers"] = keptAns.ToArray();
        WriteDB(db);
        WriteOk(ctx, "deleted");
    }

    void HandleUpdateSurveyStatus(HttpContext ctx, string id) {
        var body = GetBody(ctx);
        if (string.IsNullOrEmpty(body)) { WriteErr(ctx, "empty body"); return; }
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
        if (!found) { WriteErr(ctx, "survey not found"); return; }
        db["surveys"] = surveys;
        WriteDB(db);
        WriteOk(ctx, "updated");
    }
    // ===== Admin - Questions =====
    void HandleCreateQuestion(HttpContext ctx, string surveyId) {
        var body = GetBody(ctx);
        if (string.IsNullOrEmpty(body)) { WriteErr(ctx, "empty body"); return; }
        var input = JsonParse(body);
        var db = ReadDB();
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
            { "title", SafeStr(input, "title", "New Question") },
            { "type", SafeStr(input, "type", "single") },
            { "required", true },
            { "char_limit", 0 },
            { "sort_order", maxOrder + 1 }
        };
        var list = new List<object>(questions) { entry };
        db["questions"] = list.ToArray();
        if (input.ContainsKey("options") && input["options"] is object[]) {
            var optArr = (object[])input["options"];
            var olist = new List<object>((object[])db["options"]);
            foreach (var o in optArr) {
                var od = (Dictionary<string, object>)o;
                olist.Add(new Dictionary<string, object> {
                    { "id", NewUUID() },
                    { "question_id", qid },
                    { "content", SafeStr(od, "content", "") },
                    { "sort_order", olist.Count }
                });
            }
            db["options"] = olist.ToArray();
        }
        WriteDB(db);
        WriteOk(ctx, entry);
    }

    void HandleUpdateQuestion(HttpContext ctx, string surveyId, string qid) {
        var body = GetBody(ctx);
        if (string.IsNullOrEmpty(body)) { WriteErr(ctx, "empty body"); return; }
        var input = JsonParse(body);
        var db = ReadDB();
        object[] questions = (object[])db["questions"];
        bool found = false;
        for (int i = 0; i < questions.Length; i++) {
            var qd = (Dictionary<string, object>)questions[i];
            if (Convert.ToString(qd["id"]) == qid && Convert.ToString(qd["survey_id"]) == surveyId) {
                if (input.ContainsKey("title")) qd["title"] = SafeStr(input, "title", "");
                if (input.ContainsKey("type")) qd["type"] = SafeStr(input, "type", "");
                if (input.ContainsKey("sort_order")) qd["sort_order"] = Convert.ToInt32(input["sort_order"]);
                questions[i] = qd;
                found = true; break;
            }
        }
        if (!found) { WriteErr(ctx, "question not found"); return; }
        db["questions"] = questions;
        if (input.ContainsKey("options") && input["options"] is object[]) {
            var optArr = (object[])input["options"];
            var olist = new List<object>();
            foreach (var o in (object[])db["options"]) {
                var od = (Dictionary<string, object>)o;
                if (Convert.ToString(od["question_id"]) != qid) olist.Add(o);
            }
            foreach (var o in optArr) {
                var od = (Dictionary<string, object>)o;
                olist.Add(new Dictionary<string, object> {
                    { "id", SafeStr(od, "id", NewUUID()) },
                    { "question_id", qid },
                    { "content", SafeStr(od, "content", "") },
                    { "sort_order", olist.Count }
                });
            }
            db["options"] = olist.ToArray();
        }
        WriteDB(db);
        WriteOk(ctx, "updated");
    }

    void HandleDeleteQuestion(HttpContext ctx, string surveyId, string qid) {
        var db = ReadDB();
        object[] questions = (object[])db["questions"];
        var list = new List<object>();
        bool found = false;
        foreach (var q in questions) {
            var qd = (Dictionary<string, object>)q;
            if (Convert.ToString(qd["id"]) == qid && Convert.ToString(qd["survey_id"]) == surveyId) { found = true; continue; }
            list.Add(q);
        }
        if (!found) { WriteErr(ctx, "question not found"); return; }
        db["questions"] = list.ToArray();
        var olist = new List<object>();
        foreach (var o in (object[])db["options"]) {
            if (Convert.ToString(((Dictionary<string, object>)o)["question_id"]) != qid) olist.Add(o);
        }
        db["options"] = olist.ToArray();
        WriteDB(db);
        WriteOk(ctx, "deleted");
    }

    void HandleReorderQuestions(HttpContext ctx, string surveyId) {
        var body = GetBody(ctx);
        if (string.IsNullOrEmpty(body)) { WriteErr(ctx, "empty body"); return; }
        var input = JsonParse(body);
        if (!(input.ContainsKey("ids") && input["ids"] is object[])) {
            WriteErr(ctx, "ids required"); return;
        }
        var idsArr = (object[])input["ids"];
        var db = ReadDB();
        object[] questions = (object[])db["questions"];
        var order = new Dictionary<string, int>();
        for (int i = 0; i < idsArr.Length; i++) order[Convert.ToString(idsArr[i])] = i;
        for (int i = 0; i < questions.Length; i++) {
            var qd = (Dictionary<string, object>)questions[i];
            if (order.ContainsKey(Convert.ToString(qd["id"])))
                qd["sort_order"] = order[Convert.ToString(qd["id"])];
            questions[i] = qd;
        }
        db["questions"] = questions;
        WriteDB(db);
        WriteOk(ctx, "reordered");
    }
    // ===== Admin - Submissions & Export =====
    void HandleListSubmissions(HttpContext ctx, string surveyId) {
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
                    string qTitle = "";
                    foreach (var q in questions) {
                        var qd = (Dictionary<string, object>)q;
                        if (Convert.ToString(qd["id"]) == Convert.ToString(ad["question_id"])) {
                            qTitle = SafeStr(qd, "title", ""); break;
                        }
                    }
                    ansList.Add(new Dictionary<string, object> {
                        { "question_id", SafeStr(ad, "question_id", "") },
                        { "question_title", qTitle },
                        { "value", ad.ContainsKey("value") ? ad["value"] : "" }
                    });
                }
            }
            subList.Add(new Dictionary<string, object> {
                { "id", SafeStr(sd, "id", "") },
                { "username", SafeStr(sd, "username", "") },
                { "submitted_at", SafeStr(sd, "submitted_at", "") },
                { "answers", ansList.ToArray() }
            });
        }
        WriteOk(ctx, subList.ToArray());
    }

    void HandleExportCSV(HttpContext ctx, string surveyId) {
        var db = ReadDB();
        object[] surveys = (object[])db["surveys"];
        object[] questions = (object[])db["questions"];
        object[] submissions = (object[])db["submissions"];
        object[] answers = (object[])db["answers"];
        string title = "Survey";
        foreach (var s in surveys) {
            var sd = (Dictionary<string, object>)s;
            if (Convert.ToString(sd["id"]) == surveyId) { title = SafeStr(sd, "title", "Survey"); break; }
        }
        var qcols = new List<Dictionary<string, object>>();
        foreach (var q in questions) {
            var qd = (Dictionary<string, object>)q;
            if (Convert.ToString(qd["survey_id"]) == surveyId) qcols.Add(qd);
        }
        var sb = new StringBuilder();
        sb.Append("Submit Time,Username");
        foreach (var q in qcols) {
            var qTitle = SafeStr(q, "title", "").Replace("\"", "\"\"");
            sb.Append(",\"").Append(qTitle).Append("\"");
        }
        sb.AppendLine();
        foreach (var sub in submissions) {
            var sd = (Dictionary<string, object>)sub;
            if (Convert.ToString(sd["survey_id"]) != surveyId) continue;
            var ansMap = new Dictionary<string, object>();
            foreach (var a in answers) {
                var ad = (Dictionary<string, object>)a;
                if (Convert.ToString(ad["submission_id"]) == Convert.ToString(sd["id"]))
                    ansMap[Convert.ToString(ad["question_id"])] = ad["value"];
            }
            sb.Append(SafeStr(sd, "submitted_at", "")).Append(",").Append(SafeStr(sd, "username", ""));
            foreach (var q in qcols) {
                sb.Append(",");
                var qid = SafeStr(q, "id", "");
                if (ansMap.ContainsKey(qid)) {
                    var val = Convert.ToString(ansMap[qid]);
                    if (val.Contains(",") || val.Contains("\"") || val.Contains("\n"))
                        sb.Append("\"").Append(val.Replace("\"", "\"\"")).Append("\"");
                    else sb.Append(val);
                }
            }
            sb.AppendLine();
        }
        ctx.Response.Clear();
        ctx.Response.ContentType = "text/csv; charset=utf-8";
        ctx.Response.AddHeader("Content-Disposition", "attachment; filename=\"" + title.Replace("\"", "") + ".csv\"");
        ctx.Response.Write("\xEF\xBB\xBF");
        ctx.Response.Write(sb.ToString());
        ctx.Response.End();
    }

    // ===== Admin - User management =====
    void HandleListAdmins(HttpContext ctx) {
        var db = ReadDB();
        object[] admins = (object[])db["admins"];
        WriteOk(ctx, admins);
    }

    void HandleAddAdmin(HttpContext ctx) {
        var body = GetBody(ctx);
        if (string.IsNullOrEmpty(body)) { WriteErr(ctx, "empty body"); return; }
        var input = JsonParse(body);
        var username = SafeStr(input, "username", "");
        if (string.IsNullOrEmpty(username)) { WriteErr(ctx, "username required"); return; }
        if (username.Contains("\\")) username = username.Substring(username.IndexOf('\\') + 1);
        username = username.ToLower();
        var db = ReadDB();
        object[] admins = (object[])db["admins"];
        foreach (var a in admins) {
            var ad = (Dictionary<string, object>)a;
            if (string.Equals(SafeStr(ad, "username", ""), username, StringComparison.OrdinalIgnoreCase)) {
                WriteErr(ctx, "already admin"); return;
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
        WriteOk(ctx, "added");
    }

    void HandleRemoveAdmin(HttpContext ctx, string id) {
        var db = ReadDB();
        object[] admins = (object[])db["admins"];
        var list = new List<object>();
        bool found = false;
        foreach (var a in admins) {
            var ad = (Dictionary<string, object>)a;
            if (Convert.ToString(ad["id"]) == id) { found = true; continue; }
            list.Add(a);
        }
        if (!found) { WriteErr(ctx, "admin not found"); return; }
        db["admins"] = list.ToArray();
        WriteDB(db);
        WriteOk(ctx, "removed");
    }
}
