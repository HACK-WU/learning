package app

import (
	"context"
	"log/slog"
	"net/http"
	"net/http/pprof"
	"sync/atomic"
	"time"

	"example.com/go-order-service/internal/order"
)

type Config struct {
	Version        string
	Commit         string
	BuildTime      string
	QueueSize      int
	PaymentTimeout time.Duration
	MaxAttempts    int
	RetryDelay     time.Duration
	Logger         *slog.Logger
}

type App struct {
	store     *order.Store
	service   *order.Service
	public    *order.API
	ready     atomic.Bool
	logger    *slog.Logger
	version   string
	commit    string
	buildTime string
}

func New(store *order.Store, payment order.PaymentClient, cfg Config) *App {
	if cfg.Logger == nil {
		cfg.Logger = slog.Default()
	}
	metrics := &order.Metrics{}
	service := order.NewService(store, payment, metrics, order.ServiceConfig{
		QueueSize: cfg.QueueSize, PaymentTimeout: cfg.PaymentTimeout,
		MaxAttempts: cfg.MaxAttempts, RetryDelay: cfg.RetryDelay, Logger: cfg.Logger,
	})
	a := &App{store: store, service: service, logger: cfg.Logger, version: cfg.Version, commit: cfg.Commit, buildTime: cfg.BuildTime}
	a.public = order.NewAPI(service, order.APIConfig{
		Version: cfg.Version, Commit: cfg.Commit, BuildTime: cfg.BuildTime,
		Ready: &a.ready, Logger: cfg.Logger,
	})
	return a
}

func (a *App) Start(ctx context.Context) {
	a.service.Start(ctx)
	a.ready.Store(true)
}

func (a *App) Stop(ctx context.Context) error {
	a.ready.Store(false)
	return a.service.Stop(ctx)
}

func (a *App) Close() error { return a.store.Close() }

func (a *App) PublicHandler() http.Handler { return a.public }

func (a *App) SetReady(ready bool) { a.ready.Store(ready) }

func (a *App) Metrics() *order.Metrics { return a.service.Metrics() }

func (a *App) AdminHandler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /debug/pprof/", pprof.Index)
	mux.HandleFunc("GET /debug/pprof/cmdline", pprof.Cmdline)
	mux.HandleFunc("GET /debug/pprof/profile", pprof.Profile)
	mux.HandleFunc("GET /debug/pprof/symbol", pprof.Symbol)
	mux.HandleFunc("POST /debug/pprof/symbol", pprof.Symbol)
	mux.HandleFunc("GET /debug/pprof/trace", pprof.Trace)
	for _, name := range []string{"allocs", "block", "goroutine", "heap", "mutex", "threadcreate"} {
		mux.Handle("GET /debug/pprof/"+name, pprof.Handler(name))
	}
	return mux
}

func (a *App) VersionInfo() (version, commit, buildTime string) {
	return a.version, a.commit, a.buildTime
}
