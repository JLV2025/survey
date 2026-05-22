package middleware

import (
	"context"
	"net/http"
	"strings"
)

type contextKey string

const UsernameKey contextKey = "username"

// AuthMiddleware 身份验证中间件
// mock 模式：从配置的固定用户名获取身份
// ntlm 模式：从 HTTP Header 获取域账号（由前置 NTLM 代理注入）
func AuthMiddleware(mockUsername string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			username := mockUsername
			if username == "" {
				// 尝试从 X-Forwarded-User 或 Authorization header 获取
				username = r.Header.Get("X-Forwarded-User")
				if username == "" {
					username = r.Header.Get("X-Remote-User")
				}
			}
			// 标准化：去掉 DOMAIN\ 前缀，只保留用户名部分
			if idx := strings.LastIndex(username, "\\"); idx >= 0 {
				username = username[idx+1:]
			}
			ctx := context.WithValue(r.Context(), UsernameKey, username)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// GetUsername 从 context 中提取用户名
func GetUsername(r *http.Request) string {
	if v, ok := r.Context().Value(UsernameKey).(string); ok {
		return v
	}
	return ""
}
