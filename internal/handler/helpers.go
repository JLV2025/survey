package handler

import (
	"encoding/json"
	"net/http"

	"survey/internal/model"
)

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func okResp(data interface{}) model.APIResponse {
	return model.APIResponse{Ok: true, Data: data}
}

func errResp(msg string) model.APIResponse {
	return model.APIResponse{Ok: false, Message: msg}
}
