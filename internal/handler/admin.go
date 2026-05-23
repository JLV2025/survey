package handler

import (
	"encoding/json"
	"net/http"

	"survey/internal/middleware"
	"survey/internal/model"
	"survey/internal/store"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
)

// ====== 用户 ======

// GetMe 获取当前用户信息
func GetMe(w http.ResponseWriter, r *http.Request) {
	username := middleware.GetUsername(r)
	writeJSON(w, 200, okResp(map[string]any{
		"username": username,
		"is_admin": store.IsAdmin(username),
	}))
}

// ====== 问卷（受访者端） ======

// GetSurvey 获取问卷（含题目，仅已发布状态可公开访问）
func GetSurvey(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	survey, _ := store.GetSurvey(id)
	if survey == nil {
		writeJSON(w, 200, errResp("问卷不存在"))
		return
	}
	// 管理员可查看任何状态
	username := middleware.GetUsername(r)
	if survey.Status != "published" && !store.IsAdmin(username) {
		writeJSON(w, 200, errResp("问卷未发布"))
		return
	}
	questions := store.GetQuestions(id)
	writeJSON(w, 200, okResp(model.SurveyWithQuestions{
		Survey:    *survey,
		Questions: questions,
	}))
}

// CheckSubmitted 检查当前用户是否已提交
func CheckSubmitted(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	username := middleware.GetUsername(r)
	submitted := store.CheckSubmitted(id, username)
	writeJSON(w, 200, okResp(map[string]bool{"submitted": submitted}))
}

// SubmitSurvey 提交问卷
func SubmitSurvey(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	username := middleware.GetUsername(r)

	// 检查是否已提交
	if store.CheckSubmitted(id, username) {
		writeJSON(w, 200, errResp("您已完成此调查，无需重复填写"))
		return
	}

	// 检查问卷状态
	survey, _ := store.GetSurvey(id)
	if survey == nil || survey.Status != "published" {
		writeJSON(w, 200, errResp("问卷不存在或未发布"))
		return
	}

	var body struct {
		Answers []struct {
			QuestionID string `json:"question_id"`
			Content    string `json:"content"`
		} `json:"answers"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, 400, errResp("请求格式错误"))
		return
	}

	sub := model.Submission{
		SurveyID: id,
		Username: username,
	}
	for _, a := range body.Answers {
		sub.Answers = append(sub.Answers, model.Answer{
			ID:         uuid.New().String(),
			QuestionID: a.QuestionID,
			Content:    a.Content,
		})
	}

	if err := store.CreateSubmission(&sub); err != nil {
		writeJSON(w, 500, errResp("提交失败"))
		return
	}
	writeJSON(w, 200, okResp(map[string]string{"submission_id": sub.ID}))
}

// GetStats 获取统计
func GetStats(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	survey, _ := store.GetSurvey(id)
	if survey == nil {
		writeJSON(w, 200, errResp("问卷不存在"))
		return
	}

	questions := store.GetQuestions(id)
	submissions := store.GetSubmissions(id)

	stats := model.StatsResponse{
		SurveyTitle:      survey.Title,
		TotalSubmissions: len(submissions),
	}

	for _, q := range questions {
		qs := model.QuestionStats{
			QuestionID: q.ID,
			Title:      q.Title,
			Type:       q.Type,
		}

		if q.Type == "single" || q.Type == "multiple" {
			counts := store.CountOptions(q, submissions)
			for _, o := range q.Options {
				qs.OptionCounts = append(qs.OptionCounts, model.OptionCount{
					Content: o.Content,
					Count:   counts[o.Content],
				})
			}
		} else {
			// 文本题：收集所有答案
			for _, sub := range submissions {
				for _, a := range sub.Answers {
					if a.QuestionID == q.ID && a.Content != "" {
						qs.TextAnswers = append(qs.TextAnswers, a.Content)
					}
				}
			}
		}

		stats.Questions = append(stats.Questions, qs)
	}

	writeJSON(w, 200, okResp(stats))
}

// ====== 管理员 ======

// ListAdminSurveys 管理员获取所有问卷列表
func ListAdminSurveys(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, 200, okResp(store.ListSurveys()))
}

// CreateAdminSurvey 创建问卷
func CreateAdminSurvey(w http.ResponseWriter, r *http.Request) {
	var s model.Survey
	if err := json.NewDecoder(r.Body).Decode(&s); err != nil {
		writeJSON(w, 400, errResp("请求格式错误"))
		return
	}
	if s.Title == "" {
		writeJSON(w, 400, errResp("问卷标题不能为空"))
		return
	}
	if err := store.CreateSurvey(&s); err != nil {
		writeJSON(w, 500, errResp("创建失败"))
		return
	}
	writeJSON(w, 200, okResp(s))
}

// UpdateAdminSurvey 更新问卷元信息
func UpdateAdminSurvey(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	survey, _ := store.GetSurvey(id)
	if survey == nil {
		writeJSON(w, 404, errResp("问卷不存在"))
		return
	}
	var body model.Survey
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, 400, errResp("请求格式错误"))
		return
	}
	survey.Title = body.Title
	survey.Description = body.Description
	survey.IsAnonymous = body.IsAnonymous
	survey.Deadline = body.Deadline
	if err := store.UpdateSurvey(survey); err != nil {
		writeJSON(w, 500, errResp("更新失败"))
		return
	}
	writeJSON(w, 200, okResp(survey))
}

// DeleteAdminSurvey 删除问卷
func DeleteAdminSurvey(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	if err := store.DeleteSurvey(id); err != nil {
		writeJSON(w, 500, errResp("删除失败"))
		return
	}
	writeJSON(w, 200, okResp(nil))
}

// UpdateSurveyStatus 更新问卷状态
func UpdateSurveyStatus(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	survey, _ := store.GetSurvey(id)
	if survey == nil {
		writeJSON(w, 404, errResp("问卷不存在"))
		return
	}
	var body struct {
		Status string `json:"status"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, 400, errResp("请求格式错误"))
		return
	}
	survey.Status = body.Status
	if err := store.UpdateSurvey(survey); err != nil {
		writeJSON(w, 500, errResp("更新失败"))
		return
	}
	writeJSON(w, 200, okResp(survey))
}

// ListAdmins 管理员列表
func ListAdmins(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, 200, okResp(store.ListAdmins()))
}

// AddAdmin 添加管理员
func AddAdmin(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Username string `json:"username"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, 400, errResp("请求格式错误"))
		return
	}
	if body.Username == "" {
		writeJSON(w, 400, errResp("用户名不能为空"))
		return
	}
	name := middleware.NormalizeUsername(body.Username)
	admin, err := store.AddAdmin(name)
	if err != nil {
		writeJSON(w, 500, errResp("添加失败"))
		return
	}
	writeJSON(w, 200, okResp(admin))
}

// RemoveAdmin 删除管理员
func RemoveAdmin(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	if err := store.RemoveAdmin(id); err != nil {
		writeJSON(w, 500, errResp("删除失败"))
		return
	}
	writeJSON(w, 200, okResp(nil))
}

// ListSubmissions 查看提交列表
func ListSubmissions(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, 200, okResp(store.GetSubmissions(chi.URLParam(r, "id"))))
}
