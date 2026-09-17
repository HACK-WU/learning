package order

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestHTTPPaymentClientSuccessAndFailure(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/charge" || r.Method != http.MethodPost {
			t.Errorf("request = %s %s", r.Method, r.URL.Path)
		}
		if r.Header.Get("Content-Type") != "application/json" {
			t.Errorf("content type = %q", r.Header.Get("Content-Type"))
		}
		if strings.Contains(r.Header.Get("X-Test-Fail"), "yes") {
			http.Error(w, "declined", http.StatusBadGateway)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	t.Cleanup(server.Close)

	client, err := NewHTTPPaymentClient(server.URL, &http.Client{Timeout: time.Second})
	if err != nil {
		t.Fatal(err)
	}
	if err := client.Charge(context.Background(), Order{ID: "ord-1", AmountCents: 100}); err != nil {
		t.Fatalf("success Charge: %v", err)
	}

	// The production client deliberately treats a non-2xx response as an error;
	// the worker, not the client, owns retry policy.
	failedServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "declined", http.StatusBadGateway)
	}))
	t.Cleanup(failedServer.Close)
	failedClient, err := NewHTTPPaymentClient(failedServer.URL, nil)
	if err != nil {
		t.Fatal(err)
	}
	if err := failedClient.Charge(context.Background(), Order{ID: "ord-2", AmountCents: 100}); err == nil || !strings.Contains(err.Error(), "payment upstream status 502") {
		t.Fatalf("failure Charge = %v", err)
	}
}
