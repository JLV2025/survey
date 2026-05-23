package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"

	"survey/internal/handler"
	"survey/internal/middleware"
	"survey/internal/store"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"
)

// Config 应用配置
type Config struct {
	Port         int    `json:"port"`
	AuthMode     string `json:"auth_mode"`
	MockUsername string `json:"mock_username"`
	InitialAdmin string `json:"initial_admin"`
	DBPath       string `json:"db_path"`
}

func loadConfig() Config {
	cfg := Config{
		Port:   8080,
		DBPath: "data/survey.json",
	}
	data, err := os.ReadFile("config.json")
	if err != nil {
		log.Printf("未找到 config.json, 使用默认配置")
		return cfg
	}
	if err := json.Unmarshal(data, &cfg); err != nil {
		log.Printf("config.json 解析失败: %v", err)
	}
	return cfg
}

func main() {
	cfg := loadConfig()

	// 日志同时输出到文件和 stdout
	logFile, err := os.OpenFile("survey.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err == nil {
		log.SetOutput(io.MultiWriter(os.Stdout, logFile))
		defer logFile.Close()
	}

	// 初始化数据库
	store.Init(cfg.DBPath)
	defer store.Close()

	// 初始化首个管理员
	if cfg.InitialAdmin != "" {
		store.SeedAdmin(cfg.InitialAdmin)
	}

	// 路由
	r := chi.NewRouter()
	r.Use(chimw.Logger)
	r.Use(chimw.Recoverer)
	r.Use(middleware.AuthMiddleware(cfg.MockUsername))

	// 健康检查
	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// 静态文件
	fs := http.FileServer(http.Dir("web"))
	r.Handle("/static/*", http.StripPrefix("/static/", fs))

	// API 路由
	r.Route("/api", func(r chi.Router) {
		r.Get("/me", handler.GetMe)

		r.Get("/surveys/{id}", handler.GetSurvey)
		r.Get("/surveys/{id}/check", handler.CheckSubmitted)
		r.Post("/surveys/{id}/submit", handler.SubmitSurvey)
		r.Get("/surveys/{id}/stats", handler.GetStats)

		// 管理员路由
		r.Route("/admin", func(r chi.Router) {
			r.Get("/surveys", handler.RequireAdmin(handler.ListAdminSurveys))
			r.Post("/surveys", handler.RequireAdmin(handler.CreateAdminSurvey))
			r.Put("/surveys/{id}", handler.RequireAdmin(handler.UpdateAdminSurvey))
			r.Delete("/surveys/{id}", handler.RequireAdmin(handler.DeleteAdminSurvey))
			r.Put("/surveys/{id}/status", handler.RequireAdmin(handler.UpdateSurveyStatus))
			r.Post("/surveys/{id}/questions", handler.RequireAdmin(handler.CreateQuestion))
			r.Put("/surveys/{id}/questions/{qid}", handler.RequireAdmin(handler.UpdateQuestion))
			r.Delete("/surveys/{id}/questions/{qid}", handler.RequireAdmin(handler.DeleteQuestion))
			r.Put("/surveys/{id}/questions/reorder", handler.RequireAdmin(handler.ReorderQuestions))
			r.Get("/surveys/{id}/submissions", handler.RequireAdmin(handler.ListSubmissions))
			r.Get("/surveys/{id}/export", handler.RequireAdmin(handler.ExportExcel))
			r.Get("/users", handler.RequireAdmin(handler.ListAdmins))
			r.Post("/users", handler.RequireAdmin(handler.AddAdmin))
			r.Delete("/users/{id}", handler.RequireAdmin(handler.RemoveAdmin))
		})
	})

	// 前端 SPA 入口
	r.Get("/*", func(w http.ResponseWriter, r *http.Request) {
		http.ServeFile(w, r, "web/index.html")
	})

	log.Printf("Survey 服务启动, 端口 %d", cfg.Port)
	log.Fatal(http.ListenAndServe(fmt.Sprintf(":%d", cfg.Port), r))
}
