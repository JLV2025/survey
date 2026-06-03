package handler

import (
	"encoding/json"
	"net/http"

	"survey/internal/model"
	"survey/internal/store"

	"github.com/go-chi/chi/v5"
)

// CreateQuestion 创建题目
func CreateQuestion(w http.ResponseWriter, r *http.Request) {
	surveyID := chi.URLParam(r, "id")

	var q model.Question
	if err := json.NewDecoder(r.Body).Decode(&q); err != nil {
		writeJSON(w, 400, errResp("请求格式错误"))
		return
	}
	q.SurveyID = surveyID

	if err := store.CreateQuestion(&q); err != nil {
		writeJSON(w, 500, errResp("创建失败"))
		return
	}
	writeJSON(w, 200, okResp(q))
}

// UpdateQuestion 更新题目
func UpdateQuestion(w http.ResponseWriter, r *http.Request) {
	qid := chi.URLParam(r, "qid")

	var body model.Question
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, 400, errResp("请求格式错误"))
		return
	}
	body.ID = qid

	if err := store.UpdateQuestion(&body); err != nil {
		writeJSON(w, 500, errResp("更新失败"))
		return
	}
	writeJSON(w, 200, okResp(body))
}

// DeleteQuestion 删除题目
func DeleteQuestion(w http.ResponseWriter, r *http.Request) {
	qid := chi.URLParam(r, "qid")

	if err := store.DeleteQuestion(qid); err != nil {
		writeJSON(w, 500, errResp("删除失败"))
		return
	}
	writeJSON(w, 200, okResp(nil))
}

// ReorderQuestions 题目排序
func ReorderQuestions(w http.ResponseWriter, r *http.Request) {
	surveyID := chi.URLParam(r, "id")

	var body struct {
		IDs []string `json:"ids"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, 400, errResp("请求格式错误"))
		return
	}

	if err := store.ReorderQuestions(surveyID, body.IDs); err != nil {
		writeJSON(w, 500, errResp("排序失败"))
		return
	}
	writeJSON(w, 200, okResp(nil))
}
