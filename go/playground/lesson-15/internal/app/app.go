package app

import (
	"fmt"
	"log/slog"
	"net/http"
	"sync/atomic"
	"time"
)

// BuildInfo is the small set of release metadata that the binary reports.
type BuildInfo struct {
	Version   string
	Commit    string
	BuildTime string
}

// Hooks exposes deterministic synchronization points for the local demo.
// Production code would normally use metrics or tracing instead.
type Hooks struct {
	SlowStarted chan<- struct{}
}

// NewPublicHandler builds the public HTTP surface. pprof is intentionally not
// registered here; the management server owns that surface in main.go.
func NewPublicHandler(info BuildInfo, ready *atomic.Bool, logger *slog.Logger, hooks Hooks) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeText(w, http.StatusOK, "ok\n")
	})

	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, _ *http.Request) {
		if !ready.Load() {
			writeText(w, http.StatusServiceUnavailable, "not ready\n")
			return
		}
		writeText(w, http.StatusOK, "ready\n")
	})

	mux.HandleFunc("GET /version", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		fmt.Fprintf(w, "version=%s commit=%s build_time=%s\n", info.Version, info.Commit, info.BuildTime)
	})

	mux.HandleFunc("GET /slow", func(w http.ResponseWriter, r *http.Request) {
		if hooks.SlowStarted != nil {
			select {
			case hooks.SlowStarted <- struct{}{}:
			default:
			}
		}
		logger.Info("slow request started", slog.Int("duration_ms", 80))
		timer := time.NewTimer(80 * time.Millisecond)
		defer timer.Stop()
		<-timer.C
		logger.Info("slow request completed", slog.Int("status", http.StatusOK))
		writeText(w, http.StatusOK, "slow ok\n")
	})

	return mux
}

func writeText(w http.ResponseWriter, status int, body string) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(status)
	_, _ = w.Write([]byte(body))
}
