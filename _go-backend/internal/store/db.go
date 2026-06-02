package store

import (
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"survey/internal/model"

	"github.com/google/uuid"
)

// JSONFileStore JSON 文件存储
type JSONFileStore struct {
	mu     sync.RWMutex
	DBPath string
	Data   StoreData
}

// StoreData 持久化数据结构
type StoreData struct {
	Surveys     []model.Survey     `json:"surveys"`
	Questions   []model.Question   `json:"questions"`
	Options     []model.Option     `json:"options"`
	Submissions []model.Submission `json:"submissions"`
	Answers     []model.Answer     `json:"answers"`
	Admins      []model.Admin      `json:"admins"`
}

// DB 全局数据库实例
var DB *JSONFileStore

// Init 初始化数据库
func Init(dbPath string) {
	DB = &JSONFileStore{DBPath: dbPath}
	DB.Data = StoreData{
		Surveys:     []model.Survey{},
		Questions:   []model.Question{},
		Options:     []model.Option{},
		Submissions: []model.Submission{},
		Answers:     []model.Answer{},
		Admins:      []model.Admin{},
	}
	// 确保目录存在
	if dir := filepath.Dir(dbPath); dir != "." {
		os.MkdirAll(dir, 0755)
	}
	DB.load()
}

// Close 关闭数据库（JSON 存储无需特殊操作）
func Close() {
	if DB != nil {
		if err := DB.save(); err != nil {
			log.Printf("关闭时保存数据失败: %v", err)
		}
	}
}

func (s *JSONFileStore) load() {
	s.mu.Lock()
	defer s.mu.Unlock()
	data, err := os.ReadFile(s.DBPath)
	if err != nil {
		if os.IsNotExist(err) {
			return
		}
		log.Printf("读取数据文件失败: %v", err)
		return
	}
	if err := json.Unmarshal(data, &s.Data); err != nil {
		log.Printf("解析数据文件失败: %v", err)
	}
}

func (s *JSONFileStore) save() error {
	data, err := json.MarshalIndent(s.Data, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(s.DBPath, data, 0644)
}

// write 加写锁执行操作
func write(fn func() error) error {
	if DB == nil {
		return nil
	}
	DB.mu.Lock()
	defer DB.mu.Unlock()
	if err := fn(); err != nil {
		return err
	}
	if err := DB.save(); err != nil {
		log.Printf("写入数据文件失败: %v", err)
		return err
	}
	return nil
}

// read 加读锁执行操作
func read(fn func() error) error {
	if DB == nil {
		return nil
	}
	DB.mu.RLock()
	defer DB.mu.RUnlock()
	return fn()
}

// SeedAdmin 初始化首个管理员
func SeedAdmin(username string) {
	username = normalizeUser(username)
	if DB == nil {
		return
	}
	DB.mu.Lock()
	defer DB.mu.Unlock()
	for _, a := range DB.Data.Admins {
		if strings.EqualFold(a.Username, username) {
			return
		}
	}
	DB.Data.Admins = append(DB.Data.Admins, model.Admin{
		ID:       uuid.New().String(),
		Username: username,
	})
	if err := DB.save(); err != nil {
		log.Printf("初始化管理员失败: %v", err)
	}
}

// IsAdmin 检查是否为管理员
func IsAdmin(username string) bool {
	found := false
	read(func() error {
		for _, a := range DB.Data.Admins {
			if strings.EqualFold(a.Username, username) {
				found = true
				break
			}
		}
		return nil
	})
	return found
}

// ====== Survey ======

// ListSurveys 获取所有问卷
func ListSurveys() []model.Survey {
	var result []model.Survey
	read(func() error {
		result = make([]model.Survey, len(DB.Data.Surveys))
		copy(result, DB.Data.Surveys)
		// 按创建时间倒序
		sort.Slice(result, func(i, j int) bool {
			return result[i].CreatedAt.After(result[j].CreatedAt)
		})
		return nil
	})
	return result
}

// GetSurvey 获取单个问卷
func GetSurvey(id string) (*model.Survey, error) {
	var result *model.Survey
	read(func() error {
		for _, s := range DB.Data.Surveys {
			if s.ID == id {
				cp := s
				result = &cp
				break
			}
		}
		return nil
	})
	return result, nil
}

// GetQuestions 获取问卷的所有题目（含选项）
func GetQuestions(surveyID string) []model.Question {
	var result []model.Question
	read(func() error {
		for _, q := range DB.Data.Questions {
			if q.SurveyID == surveyID {
				q.Options = []model.Option{}
				for _, o := range DB.Data.Options {
					if o.QuestionID == q.ID {
						q.Options = append(q.Options, o)
					}
				}
				// 选项排序
				sort.Slice(q.Options, func(i, j int) bool {
					return q.Options[i].SortOrder < q.Options[j].SortOrder
				})
				result = append(result, q)
			}
		}
		// 题目排序
		sort.Slice(result, func(i, j int) bool {
			return result[i].SortOrder < result[j].SortOrder
		})
		return nil
	})
	return result
}

// CreateSurvey 创建问卷
func CreateSurvey(s *model.Survey) error {
	return write(func() error {
		s.ID = uuid.New().String()
		s.Status = "draft"
		s.CreatedAt = time.Now()
		s.UpdatedAt = time.Now()
		DB.Data.Surveys = append(DB.Data.Surveys, *s)
		return nil
	})
}

// UpdateSurvey 更新问卷
func UpdateSurvey(s *model.Survey) error {
	return write(func() error {
		for i := range DB.Data.Surveys {
			if DB.Data.Surveys[i].ID == s.ID {
				s.UpdatedAt = time.Now()
				DB.Data.Surveys[i] = *s
				return nil
			}
		}
		return nil
	})
}

// DeleteSurvey 删除问卷
func DeleteSurvey(id string) error {
	return write(func() error {
		// 删除相关题目和选项
		var qids []string
		for _, q := range DB.Data.Questions {
			if q.SurveyID == id {
				qids = append(qids, q.ID)
			}
		}
		DB.Data.Questions = filter(DB.Data.Questions, func(q model.Question) bool { return q.SurveyID != id })
		DB.Data.Options = filter(DB.Data.Options, func(o model.Option) bool {
			for _, qid := range qids {
				if o.QuestionID == qid {
					return false
				}
			}
			return true
		})
		DB.Data.Submissions = filter(DB.Data.Submissions, func(s model.Submission) bool { return s.SurveyID != id })
		DB.Data.Answers = filter(DB.Data.Answers, func(a model.Answer) bool {
			for _, sub := range DB.Data.Submissions {
				if a.SubmissionID == sub.ID {
					return false
				}
			}
			return true
		})
		DB.Data.Surveys = filter(DB.Data.Surveys, func(s model.Survey) bool { return s.ID != id })
		return nil
	})
}

// ====== Question ======

// CreateQuestion 创建题目
func CreateQuestion(q *model.Question) error {
	return write(func() error {
		q.ID = uuid.New().String()
		// 计算排序
		maxOrder := 0
		for _, eq := range DB.Data.Questions {
			if eq.SurveyID == q.SurveyID && eq.SortOrder > maxOrder {
				maxOrder = eq.SortOrder
			}
		}
		q.SortOrder = maxOrder + 1
		for i := range q.Options {
			q.Options[i].ID = uuid.New().String()
			q.Options[i].QuestionID = q.ID
			q.Options[i].SortOrder = i
			DB.Data.Options = append(DB.Data.Options, q.Options[i])
		}
		options := q.Options
		q.Options = nil
		DB.Data.Questions = append(DB.Data.Questions, *q)
		q.Options = options
		return nil
	})
}

// UpdateQuestion 更新题目
func UpdateQuestion(q *model.Question) error {
	return write(func() error {
		// 删除旧选项
		DB.Data.Options = filter(DB.Data.Options, func(o model.Option) bool { return o.QuestionID != q.ID })
		// 写入新选项
		for i := range q.Options {
			if q.Options[i].ID == "" {
				q.Options[i].ID = uuid.New().String()
			}
			q.Options[i].QuestionID = q.ID
			q.Options[i].SortOrder = i
			DB.Data.Options = append(DB.Data.Options, q.Options[i])
		}
		for i := range DB.Data.Questions {
			if DB.Data.Questions[i].ID == q.ID {
				cp := *q
				cp.Options = nil
				DB.Data.Questions[i] = cp
				return nil
			}
		}
		return nil
	})
}

// DeleteQuestion 删除题目
func DeleteQuestion(questionID string) error {
	return write(func() error {
		DB.Data.Questions = filter(DB.Data.Questions, func(q model.Question) bool { return q.ID != questionID })
		DB.Data.Options = filter(DB.Data.Options, func(o model.Option) bool { return o.QuestionID != questionID })
		return nil
	})
}

// ReorderQuestions 题目排序
func ReorderQuestions(surveyID string, ids []string) error {
	return write(func() error {
		for i, id := range ids {
			for j := range DB.Data.Questions {
				if DB.Data.Questions[j].ID == id && DB.Data.Questions[j].SurveyID == surveyID {
					DB.Data.Questions[j].SortOrder = i
				}
			}
		}
		return nil
	})
}

// ====== Submission ======

// CreateSubmission 创建提交
func CreateSubmission(sub *model.Submission) error {
	return write(func() error {
		sub.ID = uuid.New().String()
		sub.SubmittedAt = time.Now()
		for i := range sub.Answers {
			sub.Answers[i].ID = uuid.New().String()
			sub.Answers[i].SubmissionID = sub.ID
		}
		answers := sub.Answers
		sub.Answers = nil
		DB.Data.Submissions = append(DB.Data.Submissions, *sub)
		for _, a := range answers {
			DB.Data.Answers = append(DB.Data.Answers, a)
		}
		sub.Answers = answers
		return nil
	})
}

// CheckSubmitted 检查用户是否已提交
func CheckSubmitted(surveyID, username string) bool {
	submitted := false
	read(func() error {
		for _, s := range DB.Data.Submissions {
			if s.SurveyID == surveyID && strings.EqualFold(s.Username, username) {
				submitted = true
				break
			}
		}
		return nil
	})
	return submitted
}

// GetSubmissions 获取问卷提交列表
func GetSubmissions(surveyID string) []model.Submission {
	var result []model.Submission
	read(func() error {
		for _, s := range DB.Data.Submissions {
			if s.SurveyID == surveyID {
				for _, a := range DB.Data.Answers {
					if a.SubmissionID == s.ID {
						s.Answers = append(s.Answers, a)
					}
				}
				result = append(result, s)
			}
		}
		// 按提交时间排序
		sort.Slice(result, func(i, j int) bool {
			return result[i].SubmittedAt.Before(result[j].SubmittedAt)
		})
		return nil
	})
	return result
}

// ====== Admin ======

// ListAdmins 获取管理员列表
func ListAdmins() []model.Admin {
	var result []model.Admin
	read(func() error {
		result = make([]model.Admin, len(DB.Data.Admins))
		copy(result, DB.Data.Admins)
		return nil
	})
	return result
}

// AddAdmin 添加管理员
func AddAdmin(username string) (*model.Admin, error) {
	username = normalizeUser(username)
	var result *model.Admin
	err := write(func() error {
		for _, a := range DB.Data.Admins {
			if strings.EqualFold(a.Username, username) {
				return nil // 已存在
			}
		}
		a := model.Admin{
			ID:       uuid.New().String(),
			Username: username,
		}
		DB.Data.Admins = append(DB.Data.Admins, a)
		result = &a
		return nil
	})
	return result, err
}

// RemoveAdmin 删除管理员
func RemoveAdmin(id string) error {
	return write(func() error {
		DB.Data.Admins = filter(DB.Data.Admins, func(a model.Admin) bool { return a.ID != id })
		return nil
	})
}

// normalizeUser 去掉 DOMAIN\ 前缀
func normalizeUser(u string) string {
	if idx := strings.LastIndex(u, "\\"); idx >= 0 {
		return u[idx+1:]
	}
	return u
}

// ====== 辅助过滤函数 ======

func filter[T any](items []T, fn func(T) bool) []T {
	var result []T
	for _, item := range items {
		if fn(item) {
			result = append(result, item)
		}
	}
	return result
}

// CountOptions 统计选项计数
func CountOptions(q model.Question, submissions []model.Submission) map[string]int {
	counts := make(map[string]int)
	for _, o := range q.Options {
		counts[o.Content] = 0
	}
	for _, sub := range submissions {
		for _, a := range sub.Answers {
			if a.QuestionID != q.ID {
				continue
			}
			for _, o := range q.Options {
				if q.Type == "single" {
					if a.Content == o.ID {
						counts[o.Content]++
					}
				} else {
					for _, p := range strings.Split(a.Content, ",") {
						if strings.TrimSpace(p) == o.ID {
							counts[o.Content]++
						}
					}
				}
			}
		}
	}
	return counts
}
