package edgeerrors

import (
	"encoding/json"
	"net/http"
)

type envelope struct {
	Error payload `json:"error"`
}

type payload struct {
	Code      string `json:"code"`
	Message   string `json:"message"`
	RequestID string `json:"request_id,omitempty"`
}

// WriteJSON writes a structured edge error response.
func WriteJSON(w http.ResponseWriter, status int, code, message, requestID string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)

	_ = json.NewEncoder(w).Encode(envelope{
		Error: payload{
			Code:      code,
			Message:   message,
			RequestID: requestID,
		},
	})
}
