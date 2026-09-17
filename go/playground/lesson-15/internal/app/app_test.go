package app

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
)

func TestHealthAndReadiness(t *testing.T) {
	ready := new(atomic.Bool)
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	handler := NewPublicHandler(BuildInfo{Version: "test"}, ready, logger, Hooks{})

	tests := []struct {
		name       string
		path       string
		wantStatus int
		wantBody   string
	}{
		{name: "alive before ready", path: "/healthz", wantStatus: http.StatusOK, wantBody: "ok\n"},
		{name: "not ready", path: "/readyz", wantStatus: http.StatusServiceUnavailable, wantBody: "not ready\n"},
		{name: "pprof stays off public mux", path: "/debug/pprof/", wantStatus: http.StatusNotFound, wantBody: "404 page not found\n"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, tt.path, nil)
			res := httptest.NewRecorder()
			handler.ServeHTTP(res, req)
			if res.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d", res.Code, tt.wantStatus)
			}
			if body := res.Body.String(); body != tt.wantBody {
				t.Fatalf("body = %q, want %q", body, tt.wantBody)
			}
		})
	}

	ready.Store(true)
	req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	res := httptest.NewRecorder()
	handler.ServeHTTP(res, req)
	if res.Code != http.StatusOK || !strings.EqualFold(res.Body.String(), "ready\n") {
		t.Fatalf("ready response = (%d, %q), want (200, %q)", res.Code, res.Body.String(), "ready\n")
	}
}
