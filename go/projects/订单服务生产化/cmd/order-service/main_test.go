package main

import (
	"context"
	"io"
	"net"
	"net/http"
	"testing"
	"time"
)

func TestHTTPServerShutdownPreservesInFlightRequest(t *testing.T) {
	started := make(chan struct{})
	release := make(chan struct{})
	mux := http.NewServeMux()
	mux.HandleFunc("GET /slow", func(w http.ResponseWriter, _ *http.Request) {
		close(started)
		<-release
		_, _ = io.WriteString(w, "completed")
	})

	server := newHTTPServer(mux)
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	serveErr := make(chan error, 1)
	go func() { serveErr <- server.Serve(listener) }()
	t.Cleanup(func() {
		_ = listener.Close()
		select {
		case <-serveErr:
		default:
		}
	})

	result := make(chan *http.Response, 1)
	go func() {
		resp, err := http.Get("http://" + listener.Addr().String() + "/slow")
		if err == nil {
			result <- resp
			return
		}
		result <- nil
	}()
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("slow request did not start")
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), time.Second)
	shutdownDone := make(chan error, 1)
	go func() { shutdownDone <- server.Shutdown(shutdownCtx) }()
	select {
	case err := <-shutdownDone:
		if err != nil {
			t.Fatalf("Shutdown before request completion: %v", err)
		}
	case <-time.After(50 * time.Millisecond):
		// Shutdown should wait for the handler, proving this is an in-flight request.
	}
	close(release)
	cancel()

	resp := <-result
	if resp == nil {
		t.Fatal("in-flight request failed")
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusOK || string(body) != "completed" {
		t.Fatalf("response = %d %q", resp.StatusCode, body)
	}
}
