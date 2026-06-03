<%@ Language=VBScript %>
<% Option Explicit %>

<!--#include file="json.asp"-->

<%
Response.ContentType = "application/json"
Response.CodePage = 65001
Response.Charset = "UTF-8"

' ====== 全局状态 ======
Dim g_username, g_path, g_method, g_seg

' ====== 入口 ======
Call Main()

Sub Main()
    On Error Resume Next
    g_username = GetUsername()
    g_path = Request.QueryString("__path")
    g_method = UCase(Request.ServerVariables("REQUEST_METHOD"))
    g_seg = Split(g_path, "/")

    Select Case True
        ' 健康检查
        Case g_method = "GET" And g_path = "health":
            WriteJSON OkResp("OK")

        ' 公开路由 — 用户
        Case g_method = "GET" And g_path = "me":
            HandleMe()
        Case g_method = "GET" And g_path = "check-admin":
            HandleCheckAdmin()

        ' 公开路由 — 问卷
        Case g_method = "GET" And UBound(g_seg) = 1 And g_seg(0) = "surveys":
            HandleGetSurvey(g_seg(1))
        Case g_method = "GET" And UBound(g_seg) = 2 And g_seg(0) = "surveys" And g_seg(2) = "check":
            HandleCheckSubmitted(g_seg(1))
        Case g_method = "POST" And UBound(g_seg) = 2 And g_seg(0) = "surveys" And g_seg(2) = "submit":
            HandleSubmitSurvey(g_seg(1))
        Case g_method = "GET" And UBound(g_seg) = 2 And g_seg(0) = "surveys" And g_seg(2) = "stats":
            HandleGetStats(g_seg(1))

        ' 管理员路由
        Case g_seg(0) = "admin":
            If Not RequireAdmin() Then Exit Sub
            Select Case True
                Case g_method = "GET" And UBound(g_seg) = 1:
                    HandleListAdminSurveys()
                Case g_method = "POST" And UBound(g_seg) = 1:
                    HandleCreateAdminSurvey()
                Case g_method = "PUT" And UBound(g_seg) = 2:
                    HandleUpdateAdminSurvey(g_seg(2))
                Case g_method = "DELETE" And UBound(g_seg) = 2:
                    HandleDeleteAdminSurvey(g_seg(2))
                Case g_method = "PUT" And UBound(g_seg) = 3 And g_seg(3) = "status":
                    HandleUpdateSurveyStatus(g_seg(2))
                Case g_method = "POST" And UBound(g_seg) = 3 And g_seg(3) = "questions":
                    HandleCreateQuestion(g_seg(2))
                Case g_method = "PUT" And UBound(g_seg) = 4 And g_seg(3) = "questions":
                    HandleUpdateQuestion(g_seg(2), g_seg(4))
                Case g_method = "DELETE" And UBound(g_seg) = 4 And g_seg(3) = "questions":
                    HandleDeleteQuestion(g_seg(2), g_seg(4))
                Case g_method = "PUT" And UBound(g_seg) = 4 And g_seg(4) = "reorder":
                    HandleReorderQuestions(g_seg(2))
                Case g_method = "GET" And UBound(g_seg) = 3 And g_seg(3) = "submissions":
                    HandleListSubmissions(g_seg(2))
                Case g_method = "GET" And UBound(g_seg) = 3 And g_seg(3) = "export":
                    HandleExportCSV(g_seg(2))
                Case g_method = "GET" And UBound(g_seg) = 1 And g_seg(1) = "users":
                    HandleListAdmins()
                Case g_method = "POST" And UBound(g_seg) = 1 And g_seg(1) = "users":
                    HandleAddAdmin()
                Case g_method = "DELETE" And UBound(g_seg) = 2 And g_seg(1) = "users":
                    HandleRemoveAdmin(g_seg(2))
                Case Else:
                    WriteJSON ErrResp("路由不存在")
            End Select

        Case Else:
            WriteJSON ErrResp("路由不存在")
    End Select

    If Err.Number <> 0 Then
        WriteJSON ErrResp("服务器错误")
        Err.Clear
    End If
    On Error GoTo 0
End Sub

' ====== 认证 ======

Function GetUsername()
    Dim u, cfg
    u = Request.ServerVariables("LOGON_USER")
    If u = "" Then u = Request.ServerVariables("AUTH_USER")
    If u = "" Then u = Request.ServerVariables("REMOTE_USER")
    If u = "" Then
        Set cfg = LoadConfig()
        If cfg.Exists("mock_username") And cfg("mock_username") <> "" Then
            u = cfg("mock_username")
        End If
    End If
    GetUsername = StripDomain(u)
End Function

Function IsAdmin(username)
    Dim db, a, cfg, admins, i
    If username = "" Then
        IsAdmin = False
        Exit Function
    End If
    Set db = ReadDB()
    Set admins = db("admins")
    For i = 0 To UBound(admins)
        If StrComp(admins(i)("username"), username, vbTextCompare) = 0 Then
            IsAdmin = True
            Exit Function
        End If
    Next
    Set cfg = LoadConfig()
    If cfg.Exists("initial_admin") And cfg("initial_admin") <> "" Then
        Dim list, item
        list = Split(cfg("initial_admin"), ",")
        For i = 0 To UBound(list)
            item = StripDomain(Trim(list(i)))
            If StrComp(item, username, vbTextCompare) = 0 Then
                IsAdmin = True
                Exit Function
            End If
        Next
    End If
    IsAdmin = False
End Function

Function RequireAdmin()
    If g_username = "" Then
        WriteJSON ErrResp("认证失败：无法获取用户身份，请检查 IIS Windows 认证配置")
        RequireAdmin = False
        Exit Function
    End If
    If Not IsAdmin(g_username) Then
        WriteJSON ErrResp("无管理员权限")
        RequireAdmin = False
        Exit Function
    End If
    RequireAdmin = True
End Function

Function StripDomain(ByVal user)
    Dim idx
    If user = "" Then
        StripDomain = ""
        Exit Function
    End If
    idx = InStrRev(user, "\")
    If idx > 0 Then
        StripDomain = Mid(user, idx + 1)
    Else
        StripDomain = user
    End If
End Function

' ====== 工具函数 ======

Function NewUUID()
    Dim tlib, guid
    On Error Resume Next
    Set tlib = CreateObject("Scriptlet.TypeLib")
    guid = Mid(tlib.Guid, 2, 36)
    If Err.Number <> 0 Then
        Err.Clear
        guid = ManualUUID()
    End If
    On Error GoTo 0
    NewUUID = LCase(guid)
End Function

Function ManualUUID()
    Dim s, i, hexChars
    hexChars = "0123456789abcdef"
    s = ""
    For i = 1 To 36
        Dim rIdx
        rIdx = Int(16 * Rnd())
        Select Case i
            Case 9, 14, 19, 24: s = s & "-"
            Case 15: s = s & "4"
            Case 20: s = s & Mid(hexChars, 8 + Int(4 * Rnd()) + 1, 1)
            Case Else: s = s & Mid(hexChars, rIdx + 1, 1)
        End Select
    Next
    ManualUUID = s
End Function

Function NowISO()
    Dim dt, y, m, d, hh, nn, ss
    dt = Now()
    y = Year(dt)
    m = Right("0" & Month(dt), 2)
    d = Right("0" & Day(dt), 2)
    hh = Right("0" & Hour(dt), 2)
    nn = Right("0" & Minute(dt), 2)
    ss = Right("0" & Second(dt), 2)
    NowISO = y & "-" & m & "-" & d & "T" & hh & ":" & nn & ":" & ss & "+08:00"
End Function

' ====== 存储 ======

Function ReadDB()
    Dim fso, path, txt, db
    Set fso = Server.CreateObject("Scripting.FileSystemObject")
    path = Server.MapPath("data/survey.json")
    If Not fso.FileExists(path) Then
        Set db = EmptyDB()
        Set ReadDB = db
        Exit Function
    End If
    On Error Resume Next
    Set txt = fso.OpenTextFile(path, 1, False) ' 1=ForReading, False=ASCII
    Dim content
    content = txt.ReadAll()
    txt.Close()
    Set txt = Nothing
    If Len(content) = 0 Then
        Set db = EmptyDB()
    Else
        Set db = JsonParse(content)
    End If
    If Err.Number <> 0 Then
        Err.Clear
        Set db = EmptyDB()
    End If
    On Error GoTo 0
    Set ReadDB = db
End Function

Sub WriteDB(ByVal db)
    Application.Lock
    Dim fso, path, content, stream
    Set fso = Server.CreateObject("Scripting.FileSystemObject")
    path = Server.MapPath("data/survey.json")
    content = JsonStringify(db)
    Set stream = Server.CreateObject("ADODB.Stream")
    stream.Type = 2 ' adTypeText
    stream.Charset = "utf-8"
    stream.Open
    stream.WriteText content
    On Error Resume Next
    stream.SaveToFile path, 2 ' adSaveCreateOverWrite
    If Err.Number <> 0 Then
        Err.Clear
        ' 降级：直接写出
        Dim tsPath
        tsPath = path & ".tmp"
        stream.SaveToFile tsPath, 2
        If fso.FileExists(path) Then fso.DeleteFile(path)
        fso.MoveFile tsPath, path
    End If
    On Error GoTo 0
    stream.Close()
    Set stream = Nothing
    Application.Unlock
End Sub

Function EmptyDB()
    Dim db
    Set db = CreateObject("Scripting.Dictionary")
    db.Add "surveys", Array()
    db.Add "questions", Array()
    db.Add "options", Array()
    db.Add "submissions", Array()
    db.Add "answers", Array()
    db.Add "admins", Array()
    Set EmptyDB = db
End Function

Function LoadConfig()
    Dim fso, path, cfg, txt
    Set cfg = CreateObject("Scripting.Dictionary")
    Set fso = Server.CreateObject("Scripting.FileSystemObject")
    path = Server.MapPath("config.json")
    If fso.FileExists(path) Then
        On Error Resume Next
        Set txt = fso.OpenTextFile(path, 1, False)
        Dim c
        c = txt.ReadAll()
        txt.Close()
        Set txt = Nothing
        If Len(c) > 0 Then
            Set cfg = JsonParse(c)
        End If
        If Err.Number <> 0 Then Err.Clear
        On Error GoTo 0
    End If
    Set LoadConfig = cfg
End Function

' 辅助：在数组中查找元素并返回索引
Function FindById(ByVal arr, ByVal id)
    Dim i
    For i = 0 To UBound(arr)
        If arr(i)("id") = id Then
            FindById = i
            Exit Function
        End If
    Next
    FindById = -1
End Function

' 辅助：追加元素到数组
Function ArrayAppend(ByVal arr, ByVal item)
    Dim ub
    If IsEmpty(arr) Or (Not IsArray(arr)) Then
        ArrayAppend = Array(item)
        Exit Function
    End If
    ub = UBound(arr)
    If ub = -1 Then
        ' 空数组
        ArrayAppend = Array(item)
        Exit Function
    End If
    ReDim Preserve arr(ub + 1)
    Set arr(ub + 1) = item
    ArrayAppend = arr
End Function

' 辅助：从数组中删除元素
Function ArrayRemove(ByVal arr, ByVal idx)
    Dim i, j, result, ub
    ub = UBound(arr)
    If ub <= 0 Then
        ArrayRemove = Array()
        Exit Function
    End If
    ReDim result(ub - 1)
    j = 0
    For i = 0 To ub
        If i <> idx Then
            If j <= ub - 1 Then
                Set result(j) = arr(i)
                j = j + 1
            End If
        End If
    Next
    ArrayRemove = result
End Function

' ====== 用户 ======

Sub HandleMe()
    WriteJSON OkResp(DictOf("username", g_username, "is_admin", IsAdmin(g_username)))
End Sub

Sub HandleCheckAdmin()
    WriteJSON OkResp(DictOf("is_admin", IsAdmin(g_username)))
End Sub

' ====== 问卷（受访者端） ======

Sub HandleGetSurvey(ByVal id)
    Dim db, surveys, qs, survey, i
    Set db = ReadDB()
    surveys = db("surveys")
    survey = Nothing
    For i = 0 To UBound(surveys)
        If surveys(i)("id") = id Then
            Set survey = CopyDict(surveys(i))
            Exit For
        End If
    Next
    If survey Is Nothing Then
        WriteJSON ErrResp("问卷不存在")
        Exit Sub
    End If
    If survey("status") <> "published" And Not IsAdmin(g_username) Then
        WriteJSON ErrResp("问卷未发布")
        Exit Sub
    End If
    qs = GetQuestions(id)
    WriteJSON OkResp(DictOf("survey", survey, "questions", qs))
End Sub

Sub HandleCheckSubmitted(ByVal id)
    Dim db, subs, i, submitted
    Set db = ReadDB()
    subs = db("submissions")
    submitted = False
    For i = 0 To UBound(subs)
        If subs(i)("survey_id") = id And StrComp(subs(i)("username"), g_username, vbTextCompare) = 0 Then
            submitted = True
            Exit For
        End If
    Next
    WriteJSON OkResp(DictOf("submitted", submitted))
End Sub

Sub HandleSubmitSurvey(ByVal id)
    Dim db, surveys, i, survey, body, answers, ans, j, subDict, ansArr, ansItem
    Application.Lock
    Set db = ReadDB()
    surveys = db("surveys")
    survey = Nothing
    For i = 0 To UBound(surveys)
        If surveys(i)("id") = id Then
            Set survey = CopyDict(surveys(i))
            Exit For
        End If
    Next
    If survey Is Nothing Or survey("status") <> "published" Then
        Application.Unlock
        WriteJSON ErrResp("问卷不存在或未发布")
        Exit Sub
    End If
    ' 检查重复提交
    Dim subs, k
    subs = db("submissions")
    For k = 0 To UBound(subs)
        If subs(k)("survey_id") = id And StrComp(subs(k)("username"), g_username, vbTextCompare) = 0 Then
            Application.Unlock
            WriteJSON ErrResp("您已完成此调查，无需重复填写")
            Exit Sub
        End If
    Next
    Set body = ReadJSONBody()
    If Not body.Exists("answers") Or Not IsArray(body("answers")) Then
        Application.Unlock
        WriteJSON ErrResp("请求格式错误")
        Exit Sub
    End If
    answers = body("answers")
    ansArr = Array()
    For j = 0 To UBound(answers)
        Set ansItem = CreateObject("Scripting.Dictionary")
        ansItem.Add "id", NewUUID()
        ansItem.Add "submission_id", "" ' 后补
        ansItem.Add "question_id", answers(j)("question_id")
        ansItem.Add "content", answers(j)("content")
        ansArr = ArrayAppend(ansArr, ansItem)
    Next
    Set subDict = CreateObject("Scripting.Dictionary")
    subDict.Add "id", NewUUID()
    subDict.Add "survey_id", id
    subDict.Add "username", g_username
    subDict.Add "submitted_at", NowISO()
    subDict.Add "answers", ansArr
    ' 回填 submission_id
    For j = 0 To UBound(ansArr)
        ansArr(j)("submission_id") = subDict("id")
        db("answers") = ArrayAppend(db("answers"), ansArr(j))
    Next
    Set subDict("answers") = Nothing
    subDict.Remove("answers")
    db("submissions") = ArrayAppend(db("submissions"), subDict)
    WriteDB db
    WriteJSON OkResp(DictOf("submission_id", subDict("id")))
    Application.Unlock
End Sub

Sub HandleGetStats(ByVal id)
    Dim db, surveys, i, survey, questions, submissions, statsQs, qidx, q, sub, a, counts, j, o, txts, statQ
    Set db = ReadDB()
    surveys = db("surveys")
    For i = 0 To UBound(surveys)
        If surveys(i)("id") = id Then
            Set survey = CopyDict(surveys(i))
            Exit For
        End If
    Next
    If survey Is Nothing Then
        WriteJSON ErrResp("问卷不存在")
        Exit Sub
    End If
    questions = GetQuestions(id)
    submissions = GetSubmissions(id)
    statsQs = Array()
    For qidx = 0 To UBound(questions)
        Set q = questions(qidx)
        Set statQ = CreateObject("Scripting.Dictionary")
        statQ.Add "question_id", q("id")
        statQ.Add "title", q("title")
        statQ.Add "type", q("type")
        If q("type") = "single" Or q("type") = "multiple" Then
            Set counts = CreateObject("Scripting.Dictionary")
            Dim opts
            opts = q("options")
            For j = 0 To UBound(opts)
                Set o = opts(j)
                If Not counts.Exists(o("content")) Then counts.Add o("content"), 0
            Next
            For j = 0 To UBound(submissions)
                Set sub = submissions(j)
                For Each a In sub("answers")
                    If a("question_id") = q("id") Then
                        If q("type") = "single" Then
                            For Each o In opts
                                If o("id") = a("content") Then
                                    counts(o("content")) = counts(o("content")) + 1
                                End If
                            Next
                        Else
                            Dim parts, p, part
                            parts = Split(a("content"), ",")
                            For p = 0 To UBound(parts)
                                part = Trim(parts(p))
                                For Each o In opts
                                    If o("id") = part Then
                                        counts(o("content")) = counts(o("content")) + 1
                                    End If
                                Next
                            Next
                        End If
                    End If
                Next
            Next
            ReDim statQ("option_counts")(counts.Count - 1)
            j = 0
            For Each o In opts
                Set statQ("option_counts")(j) = CreateObject("Scripting.Dictionary")
                statQ("option_counts")(j).Add "content", o("content")
                statQ("option_counts")(j).Add "count", counts(o("content"))
                j = j + 1
            Next
        Else
            txts = Array()
            For j = 0 To UBound(submissions)
                Set sub = submissions(j)
                For Each a In sub("answers")
                    If a("question_id") = q("id") And a("content") <> "" Then
                        txts = ArrayAppend(txts, a("content"))
                    End If
                Next
            Next
            statQ.Add "text_answers", txts
        End If
        statsQs = ArrayAppend(statsQs, statQ)
    Next
    Dim result
    Set result = CreateObject("Scripting.Dictionary")
    result.Add "survey_title", survey("title")
    result.Add "total_submissions", UBound(submissions) + 1
    result.Add "questions", statsQs
    WriteJSON OkResp(result)
End Sub

' ====== 管理员问卷 ======

Sub HandleListAdminSurveys()
    Dim db, surveys, i, result
    Set db = ReadDB()
    surveys = db("surveys")
    result = Array()
    For i = UBound(surveys) To 0 Step -1
        result = ArrayAppend(result, CopyDict(surveys(i)))
    Next
    WriteJSON OkResp(result)
End Sub

Sub HandleCreateAdminSurvey()
    Dim db, body, s
    Set body = ReadJSONBody()
    If Not body.Exists("title") Or body("title") = "" Then
        WriteJSON ErrResp("问卷标题不能为空")
        Exit Sub
    End If
    Set s = CreateObject("Scripting.Dictionary")
    s.Add "id", NewUUID()
    s.Add "title", body("title")
    s.Add "description", SafeStr(body, "description", "")
    s.Add "status", "draft"
    s.Add "is_anonymous", SafeBool(body, "is_anonymous", False)
    s.Add "deadline", SafeStr(body, "deadline", "")
    s.Add "created_at", NowISO()
    s.Add "updated_at", NowISO()
    Set db = ReadDB()
    db("surveys") = ArrayAppend(db("surveys"), s)
    WriteDB db
    WriteJSON OkResp(s)
End Sub

Sub HandleUpdateAdminSurvey(ByVal id)
    Dim db, idx, body, s
    Set body = ReadJSONBody()
    Set db = ReadDB()
    idx = FindById(db("surveys"), id)
    If idx < 0 Then
        WriteJSON ErrResp("问卷不存在")
        Exit Sub
    End If
    Set s = db("surveys")(idx)
    If body.Exists("title") Then s("title") = body("title")
    If body.Exists("description") Then s("description") = body("description")
    If body.Exists("is_anonymous") Then s("is_anonymous") = body("is_anonymous")
    If body.Exists("deadline") Then s("deadline") = body("deadline")
    s("updated_at") = NowISO()
    WriteDB db
    WriteJSON OkResp(s)
End Sub

Sub HandleDeleteAdminSurvey(ByVal id)
    Dim db, idx, qids, i, j, q, subs
    Set db = ReadDB()
    idx = FindById(db("surveys"), id)
    If idx < 0 Then
        WriteJSON ErrResp("问卷不存在")
        Exit Sub
    End If
    ' 收集要删的 question ID
    qids = CreateObject("Scripting.Dictionary")
    For i = 0 To UBound(db("questions"))
        If db("questions")(i)("survey_id") = id Then
            qids.Add db("questions")(i)("id"), True
        End If
    Next
    ' 删 options
    Dim newOpts, o
    newOpts = Array()
    For i = 0 To UBound(db("options"))
        Set o = db("options")(i)
        If Not qids.Exists(o("question_id")) Then
            newOpts = ArrayAppend(newOpts, o)
        End If
    Next
    db("options") = newOpts
    ' 删 questions
    Dim newQs
    newQs = Array()
    For i = 0 To UBound(db("questions"))
        Set q = db("questions")(i)
        If q("survey_id") <> id Then
            newQs = ArrayAppend(newQs, q)
        End If
    Next
    db("questions") = newQs
    ' 删 submissions + answers
    Dim newSubs, newAns, subIdSet
    Set subIdSet = CreateObject("Scripting.Dictionary")
    newSubs = Array()
    For i = 0 To UBound(db("submissions"))
        If db("submissions")(i)("survey_id") <> id Then
            newSubs = ArrayAppend(newSubs, db("submissions")(i))
        Else
            subIdSet.Add db("submissions")(i)("id"), True
        End If
    Next
    db("submissions") = newSubs
    newAns = Array()
    For i = 0 To UBound(db("answers"))
        If Not subIdSet.Exists(db("answers")(i)("submission_id")) Then
            newAns = ArrayAppend(newAns, db("answers")(i))
        End If
    Next
    db("answers") = newAns
    ' 删 survey
    db("surveys") = ArrayRemove(db("surveys"), idx)
    WriteDB db
    WriteJSON OkResp(Nothing)
End Sub

Sub HandleUpdateSurveyStatus(ByVal id)
    Dim db, idx, body, s
    Set body = ReadJSONBody()
    If Not body.Exists("status") Then
        WriteJSON ErrResp("请求格式错误")
        Exit Sub
    End If
    Set db = ReadDB()
    idx = FindById(db("surveys"), id)
    If idx < 0 Then
        WriteJSON ErrResp("问卷不存在")
        Exit Sub
    End If
    Set s = db("surveys")(idx)
    s("status") = body("status")
    s("updated_at") = NowISO()
    WriteDB db
    WriteJSON OkResp(s)
End Sub

' ====== 题目 ======

Sub HandleCreateQuestion(ByVal surveyId)
    Dim db, body, q, maxOrder, i, opts, o
    Set body = ReadJSONBody()
    Set db = ReadDB()
    maxOrder = 0
    For i = 0 To UBound(db("questions"))
        If db("questions")(i)("survey_id") = surveyId And db("questions")(i)("sort_order") > maxOrder Then
            maxOrder = db("questions")(i)("sort_order")
        End If
    Next
    Set q = CreateObject("Scripting.Dictionary")
    q.Add "id", NewUUID()
    q.Add "survey_id", surveyId
    q.Add "title", body("title")
    q.Add "type", body("type")
    q.Add "required", SafeBool(body, "required", False)
    q.Add "char_limit", SafeInt(body, "char_limit", 0)
    q.Add "sort_order", maxOrder + 1
    opts = Array()
    If body.Exists("options") Then
        For i = 0 To UBound(body("options"))
            Set o = CreateObject("Scripting.Dictionary")
            o.Add "id", NewUUID()
            o.Add "question_id", q("id")
            o.Add "content", body("options")(i)("content")
            o.Add "sort_order", i
            opts = ArrayAppend(opts, o)
            db("options") = ArrayAppend(db("options"), o)
        Next
    End If
    q.Add "options", Nothing
    q.Remove("options")
    db("questions") = ArrayAppend(db("questions"), q)
    WriteDB db
    q.Add "options", opts
    WriteJSON OkResp(q)
End Sub

Sub HandleUpdateQuestion(ByVal surveyId, ByVal qid)
    Dim db, idx, body, q, i, o
    Set body = ReadJSONBody()
    Set db = ReadDB()
    idx = FindById(db("questions"), qid)
    If idx < 0 Then
        WriteJSON ErrResp("题目不存在")
        Exit Sub
    End If
    Set q = db("questions")(idx)
    If body.Exists("title") Then q("title") = body("title")
    If body.Exists("type") Then q("type") = body("type")
    If body.Exists("required") Then q("required") = body("required")
    If body.Exists("char_limit") Then q("char_limit") = SafeInt(body, "char_limit", 0)
    ' 替换选项
    Dim newOpts
    newOpts = Array()
    For i = 0 To UBound(db("options"))
        If db("options")(i)("question_id") <> qid Then
            newOpts = ArrayAppend(newOpts, db("options")(i))
        End If
    Next
    If body.Exists("options") Then
        Dim opts
        opts = body("options")
        For i = 0 To UBound(opts)
            Set o = CreateObject("Scripting.Dictionary")
            o.Add "id", NewUUID()
            o.Add "question_id", qid
            o.Add "content", opts(i)("content")
            o.Add "sort_order", i
            newOpts = ArrayAppend(newOpts, o)
        Next
    End If
    db("options") = newOpts
    WriteDB db
    WriteJSON OkResp(q)
End Sub

Sub HandleDeleteQuestion(ByVal surveyId, ByVal qid)
    Dim db, idx, newOpts, i
    Set db = ReadDB()
    idx = FindById(db("questions"), qid)
    If idx < 0 Then
        WriteJSON ErrResp("题目不存在")
        Exit Sub
    End If
    db("questions") = ArrayRemove(db("questions"), idx)
    newOpts = Array()
    For i = 0 To UBound(db("options"))
        If db("options")(i)("question_id") <> qid Then
            newOpts = ArrayAppend(newOpts, db("options")(i))
        End If
    Next
    db("options") = newOpts
    WriteDB db
    WriteJSON OkResp(Nothing)
End Sub

Sub HandleReorderQuestions(ByVal surveyId)
    Dim db, body, ids, i, j
    Set body = ReadJSONBody()
    If Not body.Exists("ids") Then
        WriteJSON ErrResp("请求格式错误")
        Exit Sub
    End If
    ids = body("ids")
    Set db = ReadDB()
    For i = 0 To UBound(ids)
        For j = 0 To UBound(db("questions"))
            If db("questions")(j)("survey_id") = surveyId And db("questions")(j)("id") = ids(i) Then
                db("questions")(j)("sort_order") = i
            End If
        Next
    Next
    WriteDB db
    WriteJSON OkResp(Nothing)
End Sub

' ====== 提交记录 + 导出 ======

Sub HandleListSubmissions(ByVal surveyId)
    WriteJSON OkResp(GetSubmissions(surveyId))
End Sub

Sub HandleExportCSV(ByVal surveyId)
    Dim db, surveys, i, survey, questions, submissions, isAnon, headers, row, j, sub, answerMap, a, q, content, parts, p, texts, o
    Set db = ReadDB()
    surveys = db("surveys")
    For i = 0 To UBound(surveys)
        If surveys(i)("id") = surveyId Then
            Set survey = CopyDict(surveys(i))
            Exit For
        End If
    Next
    If survey Is Nothing Then
        WriteJSON ErrResp("问卷不存在")
        Exit Sub
    End If
    questions = GetQuestions(surveyId)
    submissions = GetSubmissions(surveyId)
    isAnon = survey("is_anonymous")

    ' 构建表头
    headers = "序号,提交时间"
    If Not isAnon Then headers = headers & ",用户名"
    For i = 0 To UBound(questions)
        headers = headers & "," & EscapeCsvField(questions(i)("title"))
    Next

    Response.ContentType = "text/csv"
    Response.Charset = "UTF-8"
    Response.CodePage = 65001
    Response.AddHeader "Content-Disposition", "attachment; filename=""survey_" & EscapeFileName(survey("title")) & ".csv"""
    ' UTF-8 BOM
    Response.BinaryWrite ChrB(&HEF) & ChrB(&HBB) & ChrB(&HBF)
    Response.Write headers & vbCrLf

    For j = 0 To UBound(submissions)
        Set sub = submissions(j)
        row = CStr(j + 1) & "," & EscapeCsvField(sub("submitted_at"))
        If Not isAnon Then row = row & "," & EscapeCsvField(sub("username"))
        ' 构建答案映射
        Set answerMap = CreateObject("Scripting.Dictionary")
        For Each a In sub("answers")
            answerMap.Add a("question_id"), a("content")
        Next
        For i = 0 To UBound(questions)
            Set q = questions(i)
            content = ""
            If answerMap.Exists(q("id")) Then content = answerMap(q("id"))
            If q("type") = "single" Then
                For Each o In q("options")
                    If content = o("id") Then
                        content = o("content")
                        Exit For
                    End If
                Next
            ElseIf q("type") = "multiple" Then
                parts = Split(content, ",")
                texts = ""
                For p = 0 To UBound(parts)
                    For Each o In q("options")
                        If Trim(parts(p)) = o("id") Then
                            If texts <> "" Then texts = texts & "；"
                            texts = texts & o("content")
                            Exit For
                        End If
                    Next
                Next
                content = texts
            End If
            row = row & "," & EscapeCsvField(content)
        Next
        Response.Write row & vbCrLf
    Next
    Response.Flush
    Exit Sub
End Sub

' ====== 管理员 ======

Sub HandleListAdmins()
    Dim db
    Set db = ReadDB()
    WriteJSON OkResp(db("admins"))
End Sub

Sub HandleAddAdmin()
    Dim db, body, username, i, a
    Set body = ReadJSONBody()
    If Not body.Exists("username") Or body("username") = "" Then
        WriteJSON ErrResp("用户名不能为空")
        Exit Sub
    End If
    username = StripDomain(body("username"))
    Set db = ReadDB()
    ' 去重
    For i = 0 To UBound(db("admins"))
        If StrComp(db("admins")(i)("username"), username, vbTextCompare) = 0 Then
            WriteJSON ErrResp("该用户已是管理员")
            Exit Sub
        End If
    Next
    Set a = CreateObject("Scripting.Dictionary")
    a.Add "id", NewUUID()
    a.Add "username", username
    db("admins") = ArrayAppend(db("admins"), a)
    WriteDB db
    WriteJSON OkResp(a)
End Sub

Sub HandleRemoveAdmin(ByVal id)
    Dim db, idx
    Set db = ReadDB()
    idx = FindById(db("admins"), id)
    If idx < 0 Then
        WriteJSON ErrResp("管理员不存在")
        Exit Sub
    End If
    db("admins") = ArrayRemove(db("admins"), idx)
    WriteDB db
    WriteJSON OkResp(Nothing)
End Sub

' ====== 辅助查询 ======

Function GetQuestions(ByVal surveyId)
    Dim db, qs, i, q, opts, j, o, result
    Set db = ReadDB()
    qs = Array()
    ' 收集题目
    For i = 0 To UBound(db("questions"))
        If db("questions")(i)("survey_id") = surveyId Then
            Set q = CopyDict(db("questions")(i))
            opts = Array()
            For j = 0 To UBound(db("options"))
                If db("options")(j)("question_id") = q("id") Then
                    Set o = CopyDict(db("options")(j))
                    opts = ArrayAppend(opts, o)
                End If
            Next
            ' 选项排序
            If UBound(opts) >= 0 Then
                BubbleSort opts
            End If
            q.Add "options", opts
            qs = ArrayAppend(qs, q)
        End If
    Next
    ' 题目排序
    If UBound(qs) >= 0 Then
        BubbleSortByKey qs, "sort_order"
    End If
    GetQuestions = qs
End Function

Function GetSubmissions(ByVal surveyId)
    Dim db, subs, i, sub, ans, j, a, result
    Set db = ReadDB()
    subs = Array()
    For i = 0 To UBound(db("submissions"))
        If db("submissions")(i)("survey_id") = surveyId Then
            Set sub = CopyDict(db("submissions")(i))
            ans = Array()
            For j = 0 To UBound(db("answers"))
                If db("answers")(j)("submission_id") = sub("id") Then
                    Set a = CopyDict(db("answers")(j))
                    ans = ArrayAppend(ans, a)
                End If
            Next
            sub.Add "answers", ans
            subs = ArrayAppend(subs, sub)
        End If
    Next
    ' 时间升序
    If UBound(subs) >= 0 Then
        BubbleSortByKey subs, "submitted_at"
    End If
    GetSubmissions = subs
End Function

' ====== CSV 辅助 ======

Function EscapeCsvField(ByVal val)
    If InStr(val, ",") > 0 Or InStr(val, """") > 0 Or InStr(val, vbCr) > 0 Or InStr(val, vbLf) > 0 Then
        val = """" & Replace(val, """", """""") & """"
    End If
    EscapeCsvField = val
End Function

Function EscapeFileName(ByVal val)
    Dim i
    val = Replace(val, vbCr, "")
    val = Replace(val, vbLf, "")
    val = Replace(val, "\", "")
    val = Replace(val, "/", "")
    val = Replace(val, ":", "")
    val = Replace(val, "*", "")
    val = Replace(val, "?", "")
    val = Replace(val, """", "")
    val = Replace(val, "<", "")
    val = Replace(val, ">", "")
    val = Replace(val, "|", "")
    ' 移除所有控制字符 (Chr 0-31)
    For i = 0 To 31
        val = Replace(val, Chr(i), "")
    Next
    EscapeFileName = val
End Function

' ====== 排序 ======

Sub BubbleSort(ByRef arr)
    Dim i, j, tmp
    For i = 0 To UBound(arr) - 1
        For j = i + 1 To UBound(arr)
            If arr(i)("sort_order") > arr(j)("sort_order") Then
                Set tmp = arr(i)
                Set arr(i) = arr(j)
                Set arr(j) = tmp
            End If
        Next
    Next
End Sub

Sub BubbleSortByKey(ByRef arr, ByVal key)
    Dim i, j, tmp
    For i = 0 To UBound(arr) - 1
        For j = i + 1 To UBound(arr)
            If arr(i)(key) > arr(j)(key) Then
                Set tmp = arr(i)
                Set arr(i) = arr(j)
                Set arr(j) = tmp
            End If
        Next
    Next
End Sub

' ====== 安全取值 ======

Function SafeStr(ByVal dict, ByVal key, ByVal def)
    If dict.Exists(key) Then
        If TypeName(dict(key)) = "String" Then SafeStr = dict(key) Else SafeStr = def
    Else
        SafeStr = def
    End If
End Function

Function SafeBool(ByVal dict, ByVal key, ByVal def)
    If dict.Exists(key) Then
        SafeBool = CBool(dict(key))
    Else
        SafeBool = def
    End If
End Function

Function SafeInt(ByVal dict, ByVal key, ByVal def)
    If dict.Exists(key) And IsNumeric(dict(key)) Then
        SafeInt = CInt(dict(key))
    Else
        SafeInt = def
    End If
End Function

' ====== 工具 ======

Function DictOf(ByVal k1, ByVal v1, ByVal k2, ByVal v2)
    Dim d
    Set d = CreateObject("Scripting.Dictionary")
    d.Add k1, v1
    If Not IsEmpty(k2) Then d.Add k2, v2
    Set DictOf = d
End Function

Function CopyDict(ByVal src)
    Dim dst, key
    Set dst = CreateObject("Scripting.Dictionary")
    For Each key In src
        If IsArray(src(key)) Then
            dst.Add key, CopyArray(src(key))
        ElseIf IsObject(src(key)) Then
            If TypeName(src(key)) = "Dictionary" Then
                Set dst(key) = CopyDict(src(key))
            Else
                dst.Add key, src(key)
            End If
        Else
            dst.Add key, src(key)
        End If
    Next
    Set CopyDict = dst
End Function

Function CopyArray(ByVal arr)
    Dim result, i, ub
    ub = UBound(arr)
    If ub < 0 Then
        CopyArray = Array()
        Exit Function
    End If
    ReDim result(ub)
    For i = 0 To ub
        If IsObject(arr(i)) Then
            Set result(i) = CopyDict(arr(i))
        Else
            result(i) = arr(i)
        End If
    Next
    CopyArray = result
End Function

' ====== 缺失函数 ======

Function ReadJSONBody()
    Dim bytes, stream, body
    Set stream = Server.CreateObject("ADODB.Stream")
    stream.Type = 1 ' adTypeBinary
    stream.Open
    stream.LoadFromRequest
    stream.Position = 0
    stream.Type = 2 ' adTypeText
    stream.Charset = "utf-8"
    body = stream.ReadText()
    stream.Close
    Set stream = Nothing
    If Len(body) = 0 Then
        Set ReadJSONBody = CreateObject("Scripting.Dictionary")
    Else
        Set ReadJSONBody = JsonParse(body)
    End If
End Function

Function OkResp(ByVal data)
    Dim d
    Set d = CreateObject("Scripting.Dictionary")
    d.Add "ok", True
    d.Add "data", data
    Set OkResp = d
End Function

Function ErrResp(ByVal msg)
    Dim d
    Set d = CreateObject("Scripting.Dictionary")
    d.Add "ok", False
    d.Add "message", msg
    Set ErrResp = d
End Function

Sub WriteJSON(ByVal obj)
    Response.Write JsonStringify(obj)
End Sub

' ====== Application 启动（页面首次加载时初始化） ======
If IsEmpty(Application("_survey_seeded")) Then
    Application.Lock
    If IsEmpty(Application("_survey_seeded")) Then
        Randomize Timer
        Application("_survey_seeded") = True
    End If
    Application.Unlock
End If

' JSON 工具函数在单独文件中
%>
