package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/signal"
	"strings"
	"sync/atomic"
	"syscall"
	"time"

	"example.com/go-order-service/internal/app"
	"example.com/go-order-service/internal/order"
)

var (
	version   = "dev"
	commit    = "unknown"
	buildTime = "unknown"
)

type cliConfig struct {
	httpAddr   string
	adminAddr  string
	dsn        string
	paymentURL string
	demo       bool
}

func main() {
	cfg := cliConfig{}
	flag.StringVar(&cfg.httpAddr, "http-addr", envOr("ORDER_HTTP_ADDR", ":8080"), "public HTTP listen address")
	flag.StringVar(&cfg.adminAddr, "admin-addr", envOr("ORDER_ADMIN_ADDR", ":9090"), "admin HTTP listen address")
	flag.StringVar(&cfg.dsn, "db", envOr("ORDER_DB_DSN", "file:/data/orders.db"), "SQLite DSN")
	flag.StringVar(&cfg.paymentURL, "payment-url", envOr("PAYMENT_URL", ""), "payment upstream base URL")
	flag.BoolVar(&cfg.demo, "demo", false, "run a self-contained end-to-end demo and exit")
	flag.Parse()

	var err error
	if cfg.demo {
		err = runDemo()
	} else {
		err = runServer(cfg)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "order-service:", err)
		os.Exit(1)
	}
}

func runServer(cfg cliConfig) error {
	if cfg.paymentURL == "" {
		return errors.New("-payment-url or PAYMENT_URL is required outside -demo")
	}
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	ctx := context.Background()
	store, err := order.OpenStore(ctx, cfg.dsn)
	if err != nil {
		return err
	}
	defer store.Close()

	payment, err := order.NewHTTPPaymentClient(cfg.paymentURL, &http.Client{Timeout: 2 * time.Second})
	if err != nil {
		return err
	}
	a := app.New(store, payment, app.Config{
		Version: version, Commit: commit, BuildTime: buildTime,
		QueueSize: 64, PaymentTimeout: 400 * time.Millisecond,
		MaxAttempts: 2, RetryDelay: 50 * time.Millisecond, Logger: logger,
	})
	publicServer := newHTTPServer(a.PublicHandler())
	adminServer := newHTTPServer(a.AdminHandler())
	publicListener, err := net.Listen("tcp", cfg.httpAddr)
	if err != nil {
		return fmt.Errorf("listen public %s: %w", cfg.httpAddr, err)
	}
	adminListener, err := net.Listen("tcp", cfg.adminAddr)
	if err != nil {
		_ = publicListener.Close()
		return fmt.Errorf("listen admin %s: %w", cfg.adminAddr, err)
	}

	signalCtx, stopSignal := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stopSignal()
	a.Start(context.Background())
	logger.Info("order service started", "version", version, "commit", commit, "build_time", buildTime,
		"public", publicListener.Addr().String(), "admin", adminListener.Addr().String())

	serveErr := make(chan error, 2)
	go serve(serveErr, publicServer, publicListener)
	go serve(serveErr, adminServer, adminListener)
	select {
	case <-signalCtx.Done():
		logger.Info("shutdown signal received")
	case err := <-serveErr:
		if err != nil {
			logger.Error("HTTP server stopped", "err", err)
		}
	}

	a.SetReady(false)
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := publicServer.Shutdown(shutdownCtx); err != nil {
		logger.Error("public shutdown", "err", err)
	}
	if err := adminServer.Shutdown(shutdownCtx); err != nil {
		logger.Error("admin shutdown", "err", err)
	}
	if err := a.Stop(shutdownCtx); err != nil {
		return err
	}
	logger.Info("order service stopped cleanly")
	return nil
}

func newHTTPServer(handler http.Handler) *http.Server {
	return &http.Server{
		Handler:           handler,
		ReadHeaderTimeout: 2 * time.Second,
		ReadTimeout:       5 * time.Second,
		WriteTimeout:      5 * time.Second,
		IdleTimeout:       30 * time.Second,
	}
}

func serve(errCh chan<- error, server *http.Server, listener net.Listener) {
	if err := server.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
		errCh <- err
	}
}

type demoOrderResponse struct {
	Created bool `json:"created"`
	Order   struct {
		ID        string `json:"id"`
		Status    string `json:"status"`
		LastError string `json:"last_error"`
	} `json:"order"`
}

func runDemo() error {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	var paymentCalls atomic.Int64
	paymentServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		paymentCalls.Add(1)
		var payload struct {
			AmountCents int64 `json:"amount_cents"`
		}
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		if payload.AmountCents == 999 {
			http.Error(w, "card declined in demo", http.StatusBadGateway)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	defer paymentServer.Close()

	store, err := order.OpenStore(context.Background(), "file:demo?mode=memory&cache=shared")
	if err != nil {
		return err
	}
	payment, err := order.NewHTTPPaymentClient(paymentServer.URL, &http.Client{Timeout: time.Second})
	if err != nil {
		return err
	}
	a := app.New(store, payment, app.Config{
		Version: version, Commit: commit, BuildTime: buildTime,
		QueueSize: 8, PaymentTimeout: 250 * time.Millisecond,
		MaxAttempts: 2, RetryDelay: 10 * time.Millisecond, Logger: logger,
	})
	a.Start(context.Background())
	defer a.Close()
	public := httptest.NewServer(a.PublicHandler())
	admin := httptest.NewServer(a.AdminHandler())
	defer public.Close()
	defer admin.Close()

	a.SetReady(false)
	readyBefore, err := statusCode(public.Client(), public.URL+"/readyz")
	if err != nil {
		return err
	}
	a.SetReady(true)
	readyAfter, err := statusCode(public.Client(), public.URL+"/readyz")
	if err != nil {
		return err
	}
	publicPprof, err := statusCode(public.Client(), public.URL+"/debug/pprof/")
	if err != nil {
		return err
	}
	adminPprof, err := statusCode(admin.Client(), admin.URL+"/debug/pprof/")
	if err != nil {
		return err
	}
	versionStatus, versionBody, err := getBody(public.Client(), public.URL+"/version")
	if err != nil || versionStatus != http.StatusOK || !strings.Contains(versionBody, `"version":"`+version+`"`) {
		return fmt.Errorf("version endpoint status=%d body=%s err=%v", versionStatus, versionBody, err)
	}

	createStatus, first, err := createDemoOrder(public.Client(), public.URL, "demo-success", 1000)
	if err != nil {
		return err
	}
	paid, err := waitForStatus(public.Client(), public.URL, first.Order.ID, "paid")
	if err != nil {
		return err
	}
	duplicateStatus, duplicate, err := createDemoOrder(public.Client(), public.URL, "demo-success", 1000)
	if err != nil {
		return err
	}
	if duplicate.Order.ID != first.Order.ID || duplicate.Created {
		return fmt.Errorf("idempotency check failed: first=%+v duplicate=%+v", first, duplicate)
	}

	failureCreateStatus, failure, err := createDemoOrder(public.Client(), public.URL, "demo-failure", 999)
	if err != nil {
		return err
	}
	failed, err := waitForStatus(public.Client(), public.URL, failure.Order.ID, "failed")
	if err != nil {
		return err
	}
	metricsStatus, metricsBody, err := getBody(public.Client(), public.URL+"/metrics")
	if err != nil {
		return err
	}
	if !strings.Contains(metricsBody, "order_paid_total 1") || !strings.Contains(metricsBody, "order_failed_total 1") {
		return fmt.Errorf("metrics missing final counters: %s", metricsBody)
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), time.Second)
	shutdownErr := a.Stop(shutdownCtx)
	cancel()
	if shutdownErr != nil {
		return shutdownErr
	}
	fmt.Printf("project=go-order-service version=%s commit=%s build_time=%s\n", version, commit, buildTime)
	fmt.Printf("readyz_before=%d readyz_after=%d version_status=%d public_pprof=%d admin_pprof=%d\n", readyBefore, readyAfter, versionStatus, publicPprof, adminPprof)
	fmt.Printf("create_status=%d success_status=%s duplicate_status=%d duplicate_created=%t\n", createStatus, paid.Order.Status, duplicateStatus, duplicate.Created)
	fmt.Printf("failure_create_status=%d failure_status=%s retry_total=%d upstream_calls=%d\n", failureCreateStatus, failed.Order.Status, a.Metrics().PaymentRetry.Load(), paymentCalls.Load())
	fmt.Printf("metrics_status=%d counters=created:2 paid:1 failed:1\n", metricsStatus)
	fmt.Println("worker_shutdown=clean")
	return nil
}

func createDemoOrder(client *http.Client, base, key string, amount int64) (int, demoOrderResponse, error) {
	body := strings.NewReader(fmt.Sprintf(`{"amount_cents":%d}`, amount))
	req, err := http.NewRequest(http.MethodPost, base+"/orders", body)
	if err != nil {
		return 0, demoOrderResponse{}, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Idempotency-Key", key)
	resp, err := client.Do(req)
	if err != nil {
		return 0, demoOrderResponse{}, err
	}
	defer resp.Body.Close()
	var out demoOrderResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return resp.StatusCode, out, err
	}
	return resp.StatusCode, out, nil
}

func waitForStatus(client *http.Client, base, id, want string) (demoOrderResponse, error) {
	deadline := time.Now().Add(2 * time.Second)
	ticker := time.NewTicker(10 * time.Millisecond)
	defer ticker.Stop()
	for {
		resp, err := client.Get(base + "/orders/" + id)
		if err != nil {
			return demoOrderResponse{}, err
		}
		var out demoOrderResponse
		err = json.NewDecoder(resp.Body).Decode(&out)
		_ = resp.Body.Close()
		if err != nil {
			return out, err
		}
		if out.Order.Status == want {
			return out, nil
		}
		select {
		case <-ticker.C:
			if time.Now().After(deadline) {
				return out, fmt.Errorf("order %s did not reach %s", id, want)
			}
		}
	}
}

func statusCode(client *http.Client, url string) (int, error) {
	resp, err := client.Get(url)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	return resp.StatusCode, nil
}

func getBody(client *http.Client, url string) (int, string, error) {
	resp, err := client.Get(url)
	if err != nil {
		return 0, "", err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	return resp.StatusCode, string(body), err
}

func envOr(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}
