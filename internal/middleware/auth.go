package middleware

import (
	"context"
	"encoding/base64"
	"encoding/binary"
	"net/http"
	"strings"
)

type contextKey string

const UsernameKey contextKey = "username"

func AuthMiddleware(mockUsername string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			username := resolveUsername(mockUsername, r)

			// NTLM Type 1 received — send challenge (Type 2)
			if username == "" && isNTLMType1(r) {
				w.Header().Set("WWW-Authenticate", NTLMChallengeHeader())
				w.WriteHeader(http.StatusUnauthorized)
				return
			}

			// No auth on privileged routes — initiate NTLM
			if username == "" && isPrivilegedRoute(r.URL.Path) {
				if mockUsername == "" {
					w.Header().Set("WWW-Authenticate", "NTLM")
				}
				w.WriteHeader(http.StatusUnauthorized)
				return
			}

			// Normalize domain\user prefix
			if idx := strings.LastIndex(username, "\\"); idx >= 0 {
				username = username[idx+1:]
			}
			ctx := context.WithValue(r.Context(), UsernameKey, username)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// resolveUsername extracts username from mock config, forwarded headers, or NTLM auth.
func resolveUsername(mockUsername string, r *http.Request) string {
	if mockUsername != "" {
		return mockUsername
	}
	if u := r.Header.Get("X-Forwarded-User"); u != "" {
		return u
	}
	if u := r.Header.Get("X-Remote-User"); u != "" {
		return u
	}
	// Try NTLM Type 3 message
	auth := r.Header.Get("Authorization")
	username, _ := NTLMAuthUsername(auth)
	return username
}

// isNTLMType1 returns true if the request contains an NTLM Type 1 (Negotiate) message.
func isNTLMType1(r *http.Request) bool {
	auth := r.Header.Get("Authorization")
	data := NTLMAuthHeader(auth)
	if data == "" {
		return false
	}
	raw, err := base64.StdEncoding.DecodeString(data)
	if err != nil || len(raw) < 12 || string(raw[:8]) != string(ntlmSignature) {
		return false
	}
	return binary.LittleEndian.Uint32(raw[8:12]) == ntlmNegotiate
}

// isPrivilegedRoute returns true for routes that require authentication.
func isPrivilegedRoute(path string) bool {
	return strings.HasPrefix(path, "/api/admin/") || path == "/api/me"
}

func GetUsername(r *http.Request) string {
	if v, ok := r.Context().Value(UsernameKey).(string); ok {
		return v
	}
	return ""
}

func NormalizeUsername(username string) string {
	if idx := strings.LastIndex(username, "\\"); idx >= 0 {
		return username[idx+1:]
	}
	return username
}
