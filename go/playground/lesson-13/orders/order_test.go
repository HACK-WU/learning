package orders

import (
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestValidate(t *testing.T) {
	tests := []struct {
		name    string
		input   Order
		wantErr error
	}{
		{
			name:    "valid order",
			input:   Order{ID: "order-001", Quantity: 2},
			wantErr: nil,
		},
		{
			name:    "missing id",
			input:   Order{Quantity: 2},
			wantErr: ErrMissingID,
		},
		{
			name:    "zero quantity",
			input:   Order{ID: "order-001"},
			wantErr: ErrInvalidQuantity,
		},
		{
			name:    "negative quantity",
			input:   Order{ID: "order-001", Quantity: -1},
			wantErr: ErrInvalidQuantity,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := Validate(tt.input)
			if !errors.Is(err, tt.wantErr) {
				t.Errorf("Validate(%+v) error = %v, want %v", tt.input, err, tt.wantErr)
			}
		})
	}
}

func TestHandler(t *testing.T) {
	tests := []struct {
		name       string
		method     string
		body       string
		wantStatus int
		wantBody   string
	}{
		{
			name:       "accepts valid order",
			method:     http.MethodPost,
			body:       `{"id":"order-001","quantity":2}`,
			wantStatus: http.StatusAccepted,
			wantBody:   `{"status":"accepted"}`,
		},
		{
			name:       "rejects wrong method",
			method:     http.MethodGet,
			body:       `{}`,
			wantStatus: http.StatusMethodNotAllowed,
			wantBody:   "method not allowed",
		},
		{
			name:       "rejects invalid json",
			method:     http.MethodPost,
			body:       `{`,
			wantStatus: http.StatusBadRequest,
			wantBody:   "invalid json",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(tt.method, "http://example.com/orders", strings.NewReader(tt.body))
			rec := httptest.NewRecorder()

			Handler(rec, req)

			res := rec.Result()
			t.Cleanup(func() { _ = res.Body.Close() })
			gotBody, err := io.ReadAll(res.Body)
			if err != nil {
				t.Fatalf("read response body: %v", err)
			}
			if res.StatusCode != tt.wantStatus {
				t.Errorf("status = %d, want %d", res.StatusCode, tt.wantStatus)
			}
			if strings.TrimSpace(string(gotBody)) != tt.wantBody {
				t.Errorf("body = %q, want %q", gotBody, tt.wantBody)
			}
		})
	}
}
