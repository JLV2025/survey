package handler

import (
	"encoding/json"
	"net/http"

	"survey/internal/middleware"
	"survey/internal/model"
	"survey/internal/store"
)

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func okResp(data any) model.APIResponse {
	return model.APIResponse{Ok: true, Data: data}
}

func errResp(msg string) model.APIResponse {
	return model.APIResponse{Ok: false, Message: msg}
}

// RequireAdmin 包装 handler，自动校验管理员权限
func RequireAdmin(handler http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		username := middleware.GetUsername(r)
		if username == "" {
			writeJSON(w, 403, errResp("认证失败：用户名为空，请检查是否通过 NTLM 代理访问"))
			return
		}
		if !store.IsAdmin(username) {
			writeJSON(w, 403, errResp("无管理员权限"))
			return
		}
		handler(w, r)
	}
}
