package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	_ "net/http/pprof"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"

	"example.com/go-course/lesson15/internal/app"
)

var (
	version   = "dev"
	commit    = "unknown"
	buildTime = "unknown"
)

func main() {
	demo := flag.Bool("demo", false, "run a deterministic local verification and exit")
	flag.Parse()

	logger := newLogger()
	info := app.BuildInfo{Version: version, Commit: commit, BuildTime: buildTime}
	logger.Info("build metadata", slog.String("version", info.Version), slog.String("commit", info.Commit), slog.String("build_time", info.BuildTime))

	ready := new(atomic.Bool)
	slowStarted := make(chan struct{}, 1)
	publicServer := &http.Server{
		Handler:           app.NewPublicHandler(info, ready, logger, app.Hooks{SlowStarted: slowStarted}),
		ReadHeaderTimeout: time.Second,
		IdleTimeout:       5 * time.Second,
	}
	adminServer := &http.Server{
		// net/http/pprof registers on DefaultServeMux. Keeping this server on a
		// separate listener makes the public handler unable to reach those URLs.
		Handler:           http.DefaultServeMux,
		ReadHeaderTimeout: time.Second,
		IdleTimeout:       5 * time.Second,
	}

	publicListener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		logger.Error("public listener failed", slog.Any("err", err))
		os.Exit(1)
	}
	adminListener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		_ = publicListener.Close()
		logger.Error("admin listener failed", slog.Any("err", err))
		os.Exit(1)
	}

	publicDone := serve("public", publicServer, publicListener, logger)
	adminDone := serve("admin", adminServer, adminListener, logger)
	publicURL := "http://" + publicListener.Addr().String()
	adminURL := "http://" + adminListener.Addr().String()
	logger.Info("servers listening", slog.String("public", "loopback"), slog.String("admin", "loopback"))

	signalCh := make(chan os.Signal, 1)
	signal.Notify(signalCh, syscall.SIGTERM, syscall.SIGINT)
	defer signal.Stop(signalCh)

	var slowResult <-chan int
	if *demo {
		var demoErr error
		slowResult, demoErr = runDemo(publicURL, adminURL, ready, slowStarted)
		if demoErr != nil {
			logger.Error("demo failed", slog.Any("err", demoErr))
			_ = publicServer.Close()
			_ = adminServer.Close()
			os.Exit(1)
		}
	}

	sig := <-signalCh
	logger.Info("shutdown signal received", slog.String("signal", sig.String()))
	ready.Store(false)
	shutdownCtx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	logger.Info("graceful shutdown started")

	publicErr := publicServer.Shutdown(shutdownCtx)
	adminErr := adminServer.Shutdown(shutdownCtx)
	if publicErr != nil {
		logger.Error("public shutdown failed", slog.Any("err", publicErr))
	}
	if adminErr != nil {
		logger.Error("admin shutdown failed", slog.Any("err", adminErr))
	}
	_ = <-publicDone
	_ = <-adminDone
	logger.Info("graceful shutdown complete", slog.Bool("in_flight_request_preserved", publicErr == nil && adminErr == nil))
	if slowResult != nil {
		select {
		case status := <-slowResult:
			if status != http.StatusOK {
				logger.Error("demo slow request failed", slog.Int("status", status))
				os.Exit(1)
			}
			fmt.Printf("demo slow_request=%d\n", status)
		case <-time.After(2 * time.Second):
			logger.Error("demo slow request timed out")
			os.Exit(1)
		}
	}
}

func serve(name string, server *http.Server, listener net.Listener, logger *slog.Logger) <-chan error {
	done := make(chan error, 1)
	go func() {
		logger.Info("server started", slog.String("name", name))
		done <- server.Serve(listener)
	}()
	return done
}

func runDemo(publicURL, adminURL string, ready *atomic.Bool, slowStarted <-chan struct{}) (<-chan int, error) {
	client := &http.Client{Timeout: time.Second}
	readyBefore, err := getStatus(client, publicURL+"/readyz")
	if err != nil {
		return nil, err
	}
	ready.Store(true)
	health, err := getStatus(client, publicURL+"/healthz")
	if err != nil {
		return nil, err
	}
	readyAfter, err := getStatus(client, publicURL+"/readyz")
	if err != nil {
		return nil, err
	}
	publicPprof, err := getStatus(client, publicURL+"/debug/pprof/")
	if err != nil {
		return nil, err
	}
	adminPprof, err := getStatus(client, adminURL+"/debug/pprof/")
	if err != nil {
		return nil, err
	}
	fmt.Printf("demo healthz=%d readyz_before=%d readyz_after=%d public_pprof=%d admin_pprof=%d\n", health, readyBefore, readyAfter, publicPprof, adminPprof)

	slowResult := make(chan int, 1)
	go func() {
		resp, requestErr := client.Get(publicURL + "/slow")
		if requestErr != nil {
			slowResult <- 0
			return
		}
		_, _ = io.Copy(io.Discard, resp.Body)
		_ = resp.Body.Close()
		slowResult <- resp.StatusCode
	}()
	select {
	case <-slowStarted:
	case <-time.After(time.Second):
		return nil, errors.New("slow handler did not start")
	}
	if err := sendSelfSignal(syscall.SIGTERM); err != nil {
		return nil, err
	}
	return slowResult, nil
}

func getStatus(client *http.Client, url string) (int, error) {
	var lastErr error
	for attempt := 0; attempt < 40; attempt++ {
		resp, err := client.Get(url)
		if err == nil {
			defer resp.Body.Close()
			_, _ = io.Copy(io.Discard, resp.Body)
			return resp.StatusCode, nil
		}
		lastErr = err
		time.Sleep(5 * time.Millisecond)
	}
	return 0, lastErr
}

func sendSelfSignal(sig os.Signal) error {
	process, err := os.FindProcess(os.Getpid())
	if err != nil {
		return err
	}
	return process.Signal(sig)
}

func newLogger() *slog.Logger {
	options := &slog.HandlerOptions{
		ReplaceAttr: func(_ []string, attr slog.Attr) slog.Attr {
			if attr.Key == slog.TimeKey {
				return slog.Attr{}
			}
			return attr
		},
	}
	return slog.New(slog.NewJSONHandler(os.Stdout, options))
}
