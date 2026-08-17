// SurveyServer.cs — HttpListener 版调查系统后端（Windows 集成认证，零外部依赖）
// 编译: csc /nologo /codepage:65001 /r:System.ServiceProcess.dll /out:SurveyServer.exe SurveyServer.cs
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text;
using System.Threading;
using System.ServiceProcess;

// 静态文件类型表
public static class Mime {
    public static string Get(string ext) {
        switch (ext) {
            case ".html": return "text/html; charset=utf-8";
            case ".css":  return "text/css; charset=utf-8";
            case ".js":   return "application/javascript; charset=utf-8";
            case ".gif":  return "image/gif";
            case ".png":  return "image/png";
            case ".ico":  return "image/x-icon";
            case ".svg":  return "image/svg+xml";
            case ".woff": return "font/woff";
            case ".woff2":return "font/woff2";
            default:      return "application/octet-stream";
        }
    }
}

// 服务主体（业务逻辑见下方 SurveyApi 类）
public static class SurveyServer {
    static HttpListener _listener;
    static Thread _thread;
    static volatile bool _running;
    static string _root;
    static string _listen = "http://+:80/";

    public static void Start() {
        _root = SurveyApi.Root();                       // 项目根（含 web/、data/）
        _listen = ReadListen(AppDomain.CurrentDomain.BaseDirectory);  // config 在 exe 目录
        _running = true;
        _thread = new Thread(Run);
        _thread.IsBackground = true;
        _thread.Start();
    }

    public static void Stop() {
        _running = false;
        try { if (_listener != null) _listener.Close(); } catch { }
    }

    static string ReadListen(string root) {
        try {
            var cfg = Path.Combine(root, "SurveyServer.exe.config");
            if (File.Exists(cfg)) {
                var xml = File.ReadAllText(cfg);
                var m = System.Text.RegularExpressions.Regex.Match(xml, "key=\"listen\"[^>]*value=\"([^\"]+)\"");
                if (m.Success) return m.Groups[1].Value;
            }
        } catch { }
        return "http://+:80/";
    }

    static void Run() {
        string prefix = _listen;
        _listener = new HttpListener();
        _listener.Prefixes.Add(prefix);
        // 强制 Windows 集成认证：浏览器自动发送域凭据，无需输入密码
        // 未认证请求由 HttpListener 自动返回 401 并携带 WWW-Authenticate: Negotiate
        _listener.AuthenticationSchemes = AuthenticationSchemes.IntegratedWindowsAuthentication;
        _listener.Start();
        Console.WriteLine("[SurveyServer] listening " + prefix + "  root=" + _root);
        while (_running) {
            HttpListenerContext ctx;
            try {
                ctx = _listener.GetContext();
            } catch (HttpListenerException ex) {
                if (ex.ErrorCode == 401) continue;   // 客户端未提供凭据，等待浏览器重试
                break;
            } catch (Exception) {
                break;
            }
            try {
                Handle(ctx);
            } catch (Exception ex) {
                try { SurveyApi.WriteErr(ctx, "error: " + ex.Message); } catch { }
            }
        }
        try { _listener.Close(); } catch { }
    }

    static void Handle(HttpListenerContext ctx) {
        string p = ctx.Request.Url.AbsolutePath;
        if (p == "/asp/api.ashx") { SurveyApi.Route(ctx); return; }
        if (p == "/asp/diag.ashx") { SurveyApi.Diag(ctx); return; }
        ServeStatic(ctx);
    }

    static void ServeStatic(HttpListenerContext ctx) {
        string p = ctx.Request.Url.AbsolutePath;
        if (p == "/" || p == "") p = "/index.html";
        string rel = p.TrimStart('/').Replace('/', Path.DirectorySeparatorChar);
        string file = Path.GetFullPath(Path.Combine(_root, rel));
        string rootFull = Path.GetFullPath(_root);
        if (!file.StartsWith(rootFull)) { ctx.Response.StatusCode = 403; ctx.Response.Close(); return; }
        if (!File.Exists(file)) {
            // 兼容 web/index.html 布局
            if (p == "/index.html") {
                string alt = Path.Combine(_root, "web", "index.html");
                if (File.Exists(alt)) file = alt;
                else { ctx.Response.StatusCode = 404; ctx.Response.Close(); return; }
            } else { ctx.Response.StatusCode = 404; ctx.Response.Close(); return; }
        }
        string ext = Path.GetExtension(file).ToLower();
        byte[] bytes = File.ReadAllBytes(file);
        ctx.Response.StatusCode = 200;
        ctx.Response.ContentType = Mime.Get(ext);
        ctx.Response.ContentLength64 = bytes.Length;
        ctx.Response.OutputStream.Write(bytes, 0, bytes.Length);
        ctx.Response.Close();
    }
}

// Windows 服务包装
public class SurveyService : ServiceBase {
    public SurveyService() {
        ServiceName = "SurveySvc";
        CanStop = true;
        CanShutdown = true;
    }
    protected override void OnStart(string[] args) { SurveyServer.Start(); }
    protected override void OnStop() { SurveyServer.Stop(); }
    protected override void OnShutdown() { SurveyServer.Stop(); }
}

public static class Program {
    public static void Main(string[] args) {
        if (Environment.UserInteractive) {
            SurveyServer.Start();
            Console.WriteLine("[SurveyServer] running in foreground. Press Enter to stop.");
            Console.ReadLine();
            SurveyServer.Stop();
        } else {
            ServiceBase.Run(new SurveyService());
        }
    }
}

// ============================================================
// SurveyApi — 业务逻辑（存储 / JSON / 认证 / 路由 / API / CSV 导出）
// ============================================================
public static class SurveyApi {
    static object _lock = new object();

    public static string Root() {
        // 项目根 = 含 web/ 目录的位置；exe 可放在根目录或子目录（如 http-server/）
        string baseDir = AppDomain.CurrentDomain.BaseDirectory;
        if (Directory.Exists(Path.Combine(baseDir, "web"))) return baseDir;
        var dir = new DirectoryInfo(baseDir);
        while (dir != null) {
            if (Directory.Exists(Path.Combine(dir.FullName, "web")))
                return dir.FullName;
            dir = dir.Parent;
        }
        return baseDir;
    }
    static string DataPath() { return Path.Combine(Root(), "data", "survey.json"); }
    static string ConfigPath() { return Path.Combine(Root(), "config.json"); }

    // ===== 存储 =====
    static Dictionary<string, object> ReadDB() {
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

    static void WriteDB(Dictionary<string, object> db) {
        var path = DataPath();
        var dir = Path.GetDirectoryName(path);
        if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
        lock (_lock) {
            var tmp = path + ".tmp." + Guid.NewGuid().ToString("N").Substring(0, 8);
            var json = JsonStringify(db);
            File.WriteAllText(tmp, json, new UTF8Encoding(false));
            if (File.Exists(path)) File.Delete(path);
            File.Move(tmp, path);
        }
    }

    static Dictionary<string, object> EmptyDB() {
        return new Dictionary<string, object> {
            { "surveys", new object[0] },
            { "questions", new object[0] },
            { "options", new object[0] },
            { "submissions", new object[0] },
            { "answers", new object[0] },
            { "admins", new object[0] }
        };
    }

    static Dictionary<string, object> LoadConfig() {
        var path = ConfigPath();
        if (!File.Exists(path)) return new Dictionary<string, object>();
        try {
            var json = File.ReadAllText(path, Encoding.UTF8);
            if (string.IsNullOrEmpty(json)) return new Dictionary<string, object>();
            return JsonParse(json);
        } catch { return new Dictionary<string, object>(); }
    }

    // ===== JSON =====
    static string JsonStringify(object v) {
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

    static string EscapeJson(string s) {
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

    static Dictionary<string, object> JsonParse(string json) {
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

    // ===== HTTP 响应 =====
    public static void WriteJson(HttpListenerContext ctx, string json) {
        byte[] bytes = Encoding.UTF8.GetBytes(json);
        ctx.Response.StatusCode = 200;
        ctx.Response.ContentType = "application/json; charset=utf-8";
        ctx.Response.ContentLength64 = bytes.Length;
        ctx.Response.OutputStream.Write(bytes, 0, bytes.Length);
        ctx.Response.Close();
    }

    public static void WriteOk(HttpListenerContext ctx, object data) { WriteJson(ctx, "{\"ok\":true,\"data\":" + JsonStringify(data) + "}"); }
    public static void WriteErr(HttpListenerContext ctx, string msg) { WriteJson(ctx, "{\"ok\":false,\"message\":\"" + EscapeJson(msg) + "\"}"); }

    static string GetBody(HttpListenerContext ctx) {
        if (ctx.Request.ContentLength64 > 1048576) return "";
        using (var reader = new StreamReader(ctx.Request.InputStream, Encoding.UTF8)) {
            return reader.ReadToEnd();
        }
    }

    static int SafeInt(Dictionary<string, object> d, string key) { object _v; return d.TryGetValue(key, out _v) ? Convert.ToInt32(_v) : 0; }
    static string SafeStr(Dictionary<string, object> d, string key, string def) {
        object val;
        return d.TryGetValue(key, out val) ? Convert.ToString(val) : def;
    }

    static string NewUUID() { return Guid.NewGuid().ToString().ToLower(); }
    static string NowISO() { return DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss") + "+08:00"; }

    // ===== 认证 =====
    static string GetUsername(HttpListenerContext ctx) {
        // HttpListener 集成认证后直接取 Windows 身份（DOMAIN\user）
        var u = "";
        if (ctx.User != null && ctx.User.Identity != null) {
            try { u = ctx.User.Identity.Name; } catch { }
        }
        if (!string.IsNullOrEmpty(u)) {
            if (u.Contains("\\")) u = u.Substring(u.IndexOf('\\') + 1);
            else if (u.Contains("@")) u = u.Substring(0, u.IndexOf('@'));
        }
        return (u ?? "").ToLower();
    }

    static bool IsAdmin(HttpListenerContext ctx, string username) {
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

    static bool RequireAdmin(HttpListenerContext ctx) {
        var u = GetUsername(ctx);
        if (string.IsNullOrEmpty(u)) { WriteErr(ctx, "auth failed: no user identity"); return false; }
        if (!IsAdmin(ctx, u)) { WriteErr(ctx, "no admin permission"); return false; }
        return true;
    }

    static bool IsPublishedSurvey(object[] surveys, string surveyId) {
        foreach (var s in surveys) {
            var sd = (Dictionary<string, object>)s;
            if (Convert.ToString(sd["id"]) == surveyId)
                return Convert.ToString(sd["status"]) == "published";
        }
        return false;
    }

    // ===== 路由 =====
    public static void Route(HttpListenerContext ctx) {
        string method = ctx.Request.HttpMethod.ToUpperInvariant();
        string path = "";
        var qs = ctx.Request.QueryString["path"];
        if (qs != null) path = qs;
        if (path.StartsWith("/")) path = path.Substring(1);

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
            if (method == "GET" && n == 3 && seg[1] == "surveys") { HandleGetAdminSurvey(ctx, seg[2]); return; }
            if (method == "POST" && n == 2 && seg[1] == "surveys") { HandleCreateAdminSurvey(ctx); return; }
            if (method == "PUT" && n == 3 && seg[1] == "surveys") { HandleUpdateAdminSurvey(ctx, seg[2]); return; }
            if (method == "DELETE" && n == 3 && seg[1] == "surveys") { HandleDeleteAdminSurvey(ctx, seg[2]); return; }
            if (method == "PUT" && n == 4 && seg[1] == "surveys" && seg[3] == "status") { HandleUpdateSurveyStatus(ctx, seg[2]); return; }
            if (method == "POST" && n == 4 && seg[1] == "surveys" && seg[3] == "questions") { HandleCreateQuestion(ctx, seg[2]); return; }
            if (method == "PUT" && n == 5 && seg[1] == "surveys" && seg[3] == "questions" && seg[4] == "reorder") { HandleReorderQuestions(ctx, seg[2]); return; }
            if (method == "PUT" && n == 5 && seg[1] == "surveys" && seg[3] == "questions") { HandleUpdateQuestion(ctx, seg[2], seg[4]); return; }
            if (method == "DELETE" && n == 5 && seg[1] == "surveys" && seg[3] == "questions") { HandleDeleteQuestion(ctx, seg[2], seg[4]); return; }
            if (method == "GET" && n == 4 && seg[1] == "surveys" && seg[3] == "submissions") { HandleListSubmissions(ctx, seg[2]); return; }
            if (method == "GET" && n == 4 && seg[1] == "surveys" && seg[3] == "export") { HandleExportCSV(ctx, seg[2]); return; }
            if (method == "GET" && n == 2 && seg[1] == "users") { HandleListAdmins(ctx); return; }
            if (method == "POST" && n == 2 && seg[1] == "users") { HandleAddAdmin(ctx); return; }
            if (method == "DELETE" && n == 3 && seg[1] == "users") { HandleRemoveAdmin(ctx, seg[2]); return; }
            WriteErr(ctx, "route not found"); return;
        }
        WriteErr(ctx, "route not found");
    }

    // ===== 诊断页 =====
    public static void Diag(HttpListenerContext ctx) {
        var sb = new StringBuilder();
        sb.AppendLine("=== Auth Diagnostic ===");
        string name = (ctx.User != null && ctx.User.Identity != null) ? ctx.User.Identity.Name : "null";
        string type = (ctx.User != null && ctx.User.Identity != null) ? ctx.User.Identity.AuthenticationType : "";
        bool isAuth = (ctx.User != null && ctx.User.Identity != null) ? ctx.User.Identity.IsAuthenticated : false;
        sb.AppendLine("Identity.Name     : [" + name + "]");
        sb.AppendLine("AuthType          : [" + type + "]");
        sb.AppendLine("IsAuthenticated   : " + isAuth);
        sb.AppendLine("GetUsername()     : [" + GetUsername(ctx) + "]");
        sb.AppendLine("=== end ===");
        byte[] bytes = Encoding.UTF8.GetBytes(sb.ToString());
        ctx.Response.StatusCode = 200;
        ctx.Response.ContentType = "text/plain; charset=utf-8";
        ctx.Response.ContentLength64 = bytes.Length;
        ctx.Response.OutputStream.Write(bytes, 0, bytes.Length);
        ctx.Response.Close();
    }

    // ===== Handlers =====
    static void HandleMe(HttpListenerContext ctx) {
        var username = GetUsername(ctx);
        if (string.IsNullOrEmpty(username)) {
            WriteErr(ctx, "auth failed: no user identity (check Windows Authentication)");
            return;
        }
        WriteOk(ctx, new Dictionary<string, object>{
            { "username", username },
            { "is_admin", IsAdmin(ctx, username) }
        });
    }

    static void HandleCheckAdmin(HttpListenerContext ctx) {
        WriteOk(ctx, new Dictionary<string, object>{ { "is_admin", IsAdmin(ctx, GetUsername(ctx)) } });
    }

    static void HandleGetSurvey(HttpListenerContext ctx, string id) {
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

    static void HandleCheckSubmitted(HttpListenerContext ctx, string id) {
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

    static void HandleSubmitSurvey(HttpListenerContext ctx, string id) {
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
                { "value", ad.ContainsKey("value") ? ad["value"] : (ad.ContainsKey("content") ? ad["content"] : "") }
            });
        }
        var allAnswers = new List<object>((object[])db["answers"]);
        allAnswers.AddRange(ansList);
        db["answers"] = allAnswers.ToArray();
        WriteDB(db);
        WriteOk(ctx, new Dictionary<string, object>{ { "submission_id", subId } });
    }

    static void HandleGetStats(HttpListenerContext ctx, string id) {
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
        var foundSurvey = (Dictionary<string, object>)found;
        if (Convert.ToString(foundSurvey["status"]) != "published") { WriteErr(ctx, "survey not found"); return; }
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
            var textAnswers = new List<string>();
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
                    if (Convert.ToString(qd["type"]) == "text" || Convert.ToString(qd["type"]) == "textarea") {
                        if (!string.IsNullOrEmpty(val)) textAnswers.Add(val);
                    } else {
                        foreach (var token in val.Split(',')) {
                            var tid = token.Trim();
                            if (string.IsNullOrEmpty(tid)) continue;
                            foreach (var o in olist) {
                                var od = (Dictionary<string, object>)o;
                                if (Convert.ToString(od["id"]) == tid) {
                                    od["count"] = Convert.ToInt32(od["count"]) + 1;
                                    break;
                                }
                            }
                        }
                    }
                }
            }
            var qEntry = new Dictionary<string, object> {
                { "id", SafeStr(qd, "id", "") },
                { "title", SafeStr(qd, "title", "") },
                { "type", SafeStr(qd, "type", "") }
            };
            if (olist.Count > 0) qEntry["options"] = olist.ToArray();
            if (textAnswers.Count > 0) qEntry["text_answers"] = textAnswers.ToArray();
            qlist.Add(qEntry);
        }
        WriteOk(ctx, new Dictionary<string, object>{
            { "total", total },
            { "survey_title", SafeStr((Dictionary<string, object>)found, "title", "") },
            { "questions", qlist.ToArray() }
        });
    }

    // ===== Admin - Survey CRUD =====
    static void HandleListAdminSurveys(HttpListenerContext ctx) {
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

    static void HandleGetAdminSurvey(HttpListenerContext ctx, string id) {
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

    static void HandleCreateAdminSurvey(HttpListenerContext ctx) {
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

    static void HandleUpdateAdminSurvey(HttpListenerContext ctx, string id) {
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

    static void HandleDeleteAdminSurvey(HttpListenerContext ctx, string id) {
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

    static void HandleUpdateSurveyStatus(HttpListenerContext ctx, string id) {
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
    static void HandleCreateQuestion(HttpListenerContext ctx, string surveyId) {
        var body = GetBody(ctx);
        if (string.IsNullOrEmpty(body)) { WriteErr(ctx, "empty body"); return; }
        var input = JsonParse(body);
        var db = ReadDB();
        object[] surveys = (object[])db["surveys"];
        if (IsPublishedSurvey(surveys, surveyId)) { WriteErr(ctx, "survey is published, cannot modify questions"); return; }
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
            { "required", input.ContainsKey("required") ? Convert.ToBoolean(input["required"]) : true },
            { "char_limit", input.ContainsKey("char_limit") ? Convert.ToInt32(input["char_limit"]) : 0 },
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

    static void HandleUpdateQuestion(HttpListenerContext ctx, string surveyId, string qid) {
        var body = GetBody(ctx);
        if (string.IsNullOrEmpty(body)) { WriteErr(ctx, "empty body"); return; }
        var input = JsonParse(body);
        var db = ReadDB();
        object[] surveys = (object[])db["surveys"];
        if (IsPublishedSurvey(surveys, surveyId)) { WriteErr(ctx, "survey is published, cannot modify questions"); return; }
        object[] questions = (object[])db["questions"];
        bool found = false;
        for (int i = 0; i < questions.Length; i++) {
            var qd = (Dictionary<string, object>)questions[i];
            if (Convert.ToString(qd["id"]) == qid && Convert.ToString(qd["survey_id"]) == surveyId) {
                if (input.ContainsKey("title")) qd["title"] = SafeStr(input, "title", "");
                if (input.ContainsKey("type")) qd["type"] = SafeStr(input, "type", "");
                if (input.ContainsKey("required")) qd["required"] = Convert.ToBoolean(input["required"]);
                if (input.ContainsKey("char_limit")) qd["char_limit"] = Convert.ToInt32(input["char_limit"]);
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

    static void HandleDeleteQuestion(HttpListenerContext ctx, string surveyId, string qid) {
        var db = ReadDB();
        object[] surveys = (object[])db["surveys"];
        if (IsPublishedSurvey(surveys, surveyId)) { WriteErr(ctx, "survey is published, cannot modify questions"); return; }
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

    static void HandleReorderQuestions(HttpListenerContext ctx, string surveyId) {
        var body = GetBody(ctx);
        if (string.IsNullOrEmpty(body)) { WriteErr(ctx, "empty body"); return; }
        var input = JsonParse(body);
        if (!(input.ContainsKey("ids") && input["ids"] is object[])) {
            WriteErr(ctx, "ids required"); return;
        }
        var idsArr = (object[])input["ids"];
        var db = ReadDB();
        object[] surveys = (object[])db["surveys"];
        if (IsPublishedSurvey(surveys, surveyId)) { WriteErr(ctx, "survey is published, cannot modify questions"); return; }
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
    static void HandleListSubmissions(HttpListenerContext ctx, string surveyId) {
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
                        { "value", ad.ContainsKey("value") ? ad["value"] : (ad.ContainsKey("content") ? ad["content"] : "") }
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

    static void HandleExportCSV(HttpListenerContext ctx, string surveyId) {
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
        byte[] bom = new byte[] { 0xEF, 0xBB, 0xBF };
        byte[] csvBytes = Encoding.UTF8.GetBytes(sb.ToString());
        byte[] all = new byte[bom.Length + csvBytes.Length];
        Buffer.BlockCopy(bom, 0, all, 0, bom.Length);
        Buffer.BlockCopy(csvBytes, 0, all, bom.Length, csvBytes.Length);
        ctx.Response.StatusCode = 200;
        ctx.Response.ContentType = "text/csv; charset=utf-8";
        ctx.Response.AddHeader("Content-Disposition", "attachment; filename=\"" + title.Replace("\"", "") + ".csv\"");
        ctx.Response.ContentLength64 = all.Length;
        ctx.Response.OutputStream.Write(all, 0, all.Length);
        ctx.Response.Close();
    }

    // ===== Admin - User management =====
    static void HandleListAdmins(HttpListenerContext ctx) {
        var db = ReadDB();
        object[] admins = (object[])db["admins"];
        WriteOk(ctx, admins);
    }

    static void HandleAddAdmin(HttpListenerContext ctx) {
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

    static void HandleRemoveAdmin(HttpListenerContext ctx, string id) {
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
