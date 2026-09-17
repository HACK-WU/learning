package order

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"sync/atomic"
	"time"
)

type APIConfig struct {
	Version   string
	Commit    string
	BuildTime string
	Ready     *atomic.Bool
	Logger    *slog.Logger
}

type API struct {
	service   *Service
	metrics   *Metrics
	version   string
	commit    string
	buildTime string
	ready     *atomic.Bool
	logger    *slog.Logger
	mux       *http.ServeMux
}

func NewAPI(service *Service, cfg APIConfig) *API {
	if cfg.Logger == nil {
		cfg.Logger = slog.Default()
	}
	if cfg.Ready == nil {
		cfg.Ready = &atomic.Bool{}
	}
	a := &API{service: service, metrics: service.Metrics(), version: cfg.Version, commit: cfg.Commit, buildTime: cfg.BuildTime, ready: cfg.Ready, logger: cfg.Logger, mux: http.NewServeMux()}
	a.mux.HandleFunc("POST /orders", a.createOrder)
	a.mux.HandleFunc("GET /orders/{id}", a.getOrder)
	a.mux.HandleFunc("GET /healthz", a.healthz)
	a.mux.HandleFunc("GET /readyz", a.readyz)
	a.mux.HandleFunc("GET /metrics", a.metricsHandler)
	a.mux.HandleFunc("GET /version", a.versionHandler)
	return a
}

func (a *API) SetReady(ready bool) { a.ready.Store(ready) }

func (a *API) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	started := time.Now()
	sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
	a.metrics.HTTPRequests.Add(1)
	a.mux.ServeHTTP(sw, r)
	if sw.status >= http.StatusBadRequest {
		a.metrics.HTTPFailures.Add(1)
	}
	a.logger.Info("http request", "method", r.Method, "path", r.URL.Path, "status", sw.status, "duration", time.Since(started))
}

func (a *API) createOrder(w http.ResponseWriter, r *http.Request) {
	key := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	if key == "" {
		writeError(w, http.StatusBadRequest, "Idempotency-Key is required")
		return
	}

	var req CreateOrderRequest
	decoder := json.NewDecoder(io.LimitReader(r.Body, 1<<20))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	if req.AmountCents <= 0 || req.AmountCents > 100_000_000 {
		writeError(w, http.StatusBadRequest, "amount_cents must be between 1 and 100000000")
		return
	}

	o, created, err := a.service.Create(r.Context(), key, req.AmountCents)
	if err != nil {
		switch {
		case errors.Is(err, ErrIdempotencyConflict):
			writeError(w, http.StatusConflict, err.Error())
		case errors.Is(err, ErrQueueFull):
			writeError(w, http.StatusServiceUnavailable, err.Error())
		default:
			writeError(w, http.StatusInternalServerError, "create order failed")
		}
		return
	}

	status := http.StatusAccepted
	if !created && (o.Status == StatusPaid || o.Status == StatusFailed) {
		status = http.StatusOK
	}
	writeJSON(w, status, map[string]any{"created": created, "order": o})
}

func (a *API) getOrder(w http.ResponseWriter, r *http.Request) {
	o, err := a.service.Get(r.Context(), r.PathValue("id"))
	if errors.Is(err, ErrNotFound) {
		writeError(w, http.StatusNotFound, "order not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "get order failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"order": o})
}

func (a *API) healthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "version": a.version})
}

func (a *API) readyz(w http.ResponseWriter, _ *http.Request) {
	if !a.ready.Load() {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "not_ready"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func (a *API) metricsHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4")
	_, _ = io.WriteString(w, a.metrics.Render())
}

func (a *API) versionHandler(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"version": a.version, "commit": a.commit, "build_time": a.buildTime,
	})
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

func (w *statusWriter) Write(body []byte) (int, error) {
	if w.status == 0 {
		w.status = http.StatusOK
	}
	return w.ResponseWriter.Write(body)
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		return
	}
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

var _ http.Handler = (*API)(nil)
