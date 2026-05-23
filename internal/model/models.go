package model

import "time"

// Survey 问卷
type Survey struct {
	ID          string    `json:"id"`
	Title       string    `json:"title"`
	Description string    `json:"description"`
	Status      string    `json:"status"` // draft, published, closed
	IsAnonymous bool      `json:"is_anonymous"`
	Deadline    string    `json:"deadline"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// Question 题目
type Question struct {
	ID        string   `json:"id"`
	SurveyID  string   `json:"survey_id"`
	Title     string   `json:"title"`
	Type      string   `json:"type"` // single, multiple, text, textarea
	Required  bool     `json:"required"`
	CharLimit int      `json:"char_limit"`
	SortOrder int      `json:"sort_order"`
	Options   []Option `json:"options,omitempty"`
}

// Option 选项
type Option struct {
	ID         string `json:"id"`
	QuestionID string `json:"question_id"`
	Content    string `json:"content"`
	SortOrder  int    `json:"sort_order"`
}

// Submission 提交记录
type Submission struct {
	ID          string    `json:"id"`
	SurveyID    string    `json:"survey_id"`
	Username    string    `json:"username"`
	SubmittedAt time.Time `json:"submitted_at"`
	Answers     []Answer  `json:"answers,omitempty"`
}

// Answer 答案
type Answer struct {
	ID           string `json:"id"`
	SubmissionID string `json:"submission_id"`
	QuestionID   string `json:"question_id"`
	Content      string `json:"content"`
}

// Admin 管理员
type Admin struct {
	ID       string `json:"id"`
	Username string `json:"username"`
}

// SurveyWithQuestions 问卷 + 题目
type SurveyWithQuestions struct {
	Survey    Survey     `json:"survey"`
	Questions []Question `json:"questions"`
}

// StatsResponse 统计响应
type StatsResponse struct {
	SurveyTitle      string          `json:"survey_title"`
	TotalSubmissions int             `json:"total_submissions"`
	Questions        []QuestionStats `json:"questions"`
}

// QuestionStats 题目统计
type QuestionStats struct {
	QuestionID   string        `json:"question_id"`
	Title        string        `json:"title"`
	Type         string        `json:"type"`
	OptionCounts []OptionCount `json:"option_counts,omitempty"`
	TextAnswers  []string      `json:"text_answers,omitempty"`
}

// OptionCount 选项计数
type OptionCount struct {
	Content string `json:"content"`
	Count   int    `json:"count"`
}

// APIResponse 通用 API 响应
type APIResponse struct {
	Ok      bool   `json:"ok"`
	Data    any    `json:"data,omitempty"`
	Message string `json:"message,omitempty"`
}
