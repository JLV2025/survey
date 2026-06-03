<%
' json.asp — JSON 编解码工具（纯 VBScript 实现）
' 支持: Object (Dictionary), Array, String, Number, Boolean, Null

' ====== 编码：VBScript → JSON 字符串 ======

Function JsonStringify(ByVal v)
    JsonStringify = StringifyValue(v)
End Function

Function StringifyValue(ByVal v)
    Dim t
    t = VarType(v)
    Select Case True
        Case IsNull(v), IsEmpty(v):
            StringifyValue = "null"
        Case t = 11: ' vbBoolean
            If v Then StringifyValue = "true" Else StringifyValue = "false"
        Case t = 7: ' vbDate
            StringifyValue = """" & DateToISO(v) & """"
        Case t >= 2 And t <= 5: ' vbInteger/vbLong/vbSingle/vbDouble
            StringifyValue = CStr(v)
        Case t = 8: ' vbString
            StringifyValue = """" & EscapeString(v) & """"
        Case IsObject(v):
            If TypeName(v) = "Dictionary" Then
                StringifyValue = StringifyDict(v)
            Else
                StringifyValue = "null"
            End If
        Case t >= 8192: ' vbArray
            StringifyValue = StringifyArray(v)
        Case Else:
            StringifyValue = "null"
    End Select
End Function

Function StringifyDict(ByVal d)
    Dim keys, first, k, v
    first = True
    StringifyDict = "{"
    keys = d.Keys
    For Each k In keys
        If Not first Then StringifyDict = StringifyDict & ","
        StringifyDict = StringifyDict & """" & EscapeString(CStr(k)) & """:"
        If IsObject(d(k)) And TypeName(d(k)) = "Dictionary" Then
            StringifyDict = StringifyDict & StringifyValue(d(k))
        Else
            StringifyDict = StringifyDict & StringifyValue(d(k))
        End If
        first = False
    Next
    StringifyDict = StringifyDict & "}"
End Function

Function StringifyArray(ByVal arr)
    Dim i, first
    first = True
    StringifyArray = "["
    For i = 0 To UBound(arr)
        If Not first Then StringifyArray = StringifyArray & ","
        If IsObject(arr(i)) Then
            StringifyArray = StringifyArray & StringifyValue(arr(i))
        Else
            StringifyArray = StringifyArray & StringifyValue(arr(i))
        End If
        first = False
    Next
    StringifyArray = StringifyArray & "]"
End Function

Function EscapeString(ByVal s)
    s = Replace(s, "\", "\\")
    s = Replace(s, """", "\""")
    s = Replace(s, vbCr, "\r")
    s = Replace(s, vbLf, "\n")
    s = Replace(s, vbTab, "\t")
    EscapeString = s
End Function

Function DateToISO(ByVal dt)
    DateToISO = Year(dt) & "-" & Right("0" & Month(dt), 2) & "-" & Right("0" & Day(dt), 2) & _
        "T" & Right("0" & Hour(dt), 2) & ":" & Right("0" & Minute(dt), 2) & ":" & Right("0" & Second(dt), 2)
End Function

' ====== 解码：JSON 字符串 → VBScript ======

Dim g_pos, g_src, g_len

Function JsonParse(ByVal s)
    g_src = s
    g_len = Len(s)
    g_pos = 1
    SkipSpaces()
    Set JsonParse = ParseValue()
End Function

Function ParseValue()
    Dim c
    SkipSpaces()
    If g_pos > g_len Then
        Set ParseValue = Nothing
        Exit Function
    End If
    c = Mid(g_src, g_pos, 1)
    Select Case c
        Case "{": Set ParseValue = ParseObject()
        Case "[": Set ParseValue = ParseArray()
        Case """": Set ParseValue = ParseString()
        Case "t", "f": Set ParseValue = ParseBoolean()
        Case "n": Set ParseValue = ParseNull()
        Case Else:
            If IsNumeric(c) Or c = "-" Then
                Set ParseValue = ParseNumber()
            Else
                g_pos = g_pos + 1
                Set ParseValue = Nothing
            End If
    End Select
End Function

Sub SkipSpaces()
    Do While g_pos <= g_len
        Dim c
        c = Mid(g_src, g_pos, 1)
        If c <> " " And c <> vbTab And c <> vbCr And c <> vbLf Then Exit Do
        g_pos = g_pos + 1
    Loop
End Sub

Function ParseObject()
    Dim d
    Set d = CreateObject("Scripting.Dictionary")
    g_pos = g_pos + 1 ' skip {
    SkipSpaces()
    If g_pos <= g_len Then
        If Mid(g_src, g_pos, 1) = "}" Then
            g_pos = g_pos + 1
            Set ParseObject = d
            Exit Function
        End If
    End If
    Do While g_pos <= g_len
        Dim key, val
        SkipSpaces()
        key = ParseString()
        SkipSpaces()
        If g_pos > g_len Then Exit Do
        If Mid(g_src, g_pos, 1) = ":" Then g_pos = g_pos + 1
        SkipSpaces()
        Set val = ParseValue()
        If Not val Is Nothing Then
            d.Add key, val
        End If
        SkipSpaces()
        If g_pos > g_len Then Exit Do
        If Mid(g_src, g_pos, 1) = "}" Then
            g_pos = g_pos + 1
            Exit Do
        End If
        If Mid(g_src, g_pos, 1) = "," Then g_pos = g_pos + 1
    Loop
    Set ParseObject = d
End Function

Function ParseArray()
    Dim arr, item
    arr = Array()
    g_pos = g_pos + 1 ' skip [
    SkipSpaces()
    If g_pos <= g_len Then
        If Mid(g_src, g_pos, 1) = "]" Then
            g_pos = g_pos + 1
            ParseArray = arr
            Exit Function
        End If
    End If
    Do While g_pos <= g_len
        SkipSpaces()
        Set item = ParseValue()
        If Not item Is Nothing Then
            arr = ArrayAppendVal(arr, item)
        End If
        SkipSpaces()
        If g_pos > g_len Then Exit Do
        If Mid(g_src, g_pos, 1) = "]" Then
            g_pos = g_pos + 1
            Exit Do
        End If
        If Mid(g_src, g_pos, 1) = "," Then g_pos = g_pos + 1
    Loop
    ParseArray = arr
End Function

Function ParseString()
    Dim result, c, escaped
    result = ""
    g_pos = g_pos + 1 ' skip opening quote
    escaped = False
    Do While g_pos <= g_len
        c = Mid(g_src, g_pos, 1)
        If escaped Then
            Select Case c
                Case """": result = result & """"
                Case "\": result = result & "\"
                Case "/": result = result & "/"
                Case "b": result = result & Chr(8)
                Case "f": result = result & Chr(12)
                Case "n": result = result & vbLf
                Case "r": result = result & vbCr
                Case "t": result = result & vbTab
                Case "u":
                    g_pos = g_pos + 1
                    If g_pos + 3 <= g_len Then
                        Dim hexStr, code
                        hexStr = Mid(g_src, g_pos, 4)
                        code = CLng("&H" & hexStr)
                        result = result & ChrW(code)
                        g_pos = g_pos + 3
                    End If
                Case Else: result = result & c
            End Select
            escaped = False
        ElseIf c = "\" Then
            escaped = True
        ElseIf c = """" Then
            g_pos = g_pos + 1
            Exit Do
        Else
            result = result & c
        End If
        g_pos = g_pos + 1
    Loop
    ParseString = result
End Function

Function ParseNumber()
    Dim start, numStr
    start = g_pos
    Do While g_pos <= g_len
        Dim c
        c = Mid(g_src, g_pos, 1)
        If InStr("0123456789.-+eE", c) = 0 Then Exit Do
        g_pos = g_pos + 1
    Loop
    numStr = Mid(g_src, start, g_pos - start)
    If IsNumeric(numStr) Then
        ParseNumber = CDbl(numStr)
    Else
        ParseNumber = 0
    End If
End Function

Function ParseBoolean()
    If Mid(g_src, g_pos, 4) = "true" Then
        g_pos = g_pos + 4
        ParseBoolean = True
    Else
        g_pos = g_pos + 5
        ParseBoolean = False
    End If
End Function

Function ParseNull()
    g_pos = g_pos + 4
    ParseNull = Null
End Function

' 辅助：追加标量到数组
Function ArrayAppendVal(ByVal arr, ByVal val)
    Dim ub
    If Not IsArray(arr) Then
        ArrayAppendVal = Array(val)
        Exit Function
    End If
    ub = UBound(arr)
    If ub = -1 Then
        ArrayAppendVal = Array(val)
        Exit Function
    End If
    ReDim Preserve arr(ub + 1)
    If IsObject(val) Then
        Set arr(ub + 1) = val
    Else
        arr(ub + 1) = val
    End If
    ArrayAppendVal = arr
End Function
%>
