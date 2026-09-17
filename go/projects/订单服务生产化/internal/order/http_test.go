package order

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestAPIValidationIdempotencyAndQuery(t *testing.T) {
	store := testStore(t)
	svc := NewService(store, &fakePayment{}, nil, ServiceConfig{QueueSize: 4, PaymentTimeout: time.Second})
	svc.Start(context.Background())
	stopService(t, svc)
	api := NewAPI(svc, APIConfig{Version: "test"})
	server := httptest.NewServer(api)
	t.Cleanup(server.Close)

	status, _ := postJSON(t, server.Client(), server.URL, "", `{"amount_cents":100}`)
	if status != http.StatusBadRequest {
		t.Fatalf("missing idempotency key status=%d", status)
	}
	status, _ = postJSON(t, server.Client(), server.URL, "same", `{"amount_cents":100}`)
	if status != http.StatusAccepted {
		t.Fatalf("create status=%d", status)
	}
	status, _ = postJSON(t, server.Client(), server.URL, "same", `{"amount_cents":200}`)
	if status != http.StatusConflict {
		t.Fatalf("idempotency conflict status=%d", status)
	}

	resp, err := server.Client().Get(server.URL + "/orders/missing")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("missing order status=%d", resp.StatusCode)
	}

	resp, err = server.Client().Get(server.URL + "/metrics")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("metrics status=%d", resp.StatusCode)
	}
}

func TestAPIReadiness(t *testing.T) {
	store := testStore(t)
	svc := NewService(store, &fakePayment{}, nil, ServiceConfig{})
	api := NewAPI(svc, APIConfig{Version: "test"})
	server := httptest.NewServer(api)
	t.Cleanup(server.Close)

	resp, err := server.Client().Get(server.URL + "/readyz")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("initial readiness status=%d", resp.StatusCode)
	}
	api.SetReady(true)
	resp, err = server.Client().Get(server.URL + "/readyz")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("ready status=%d", resp.StatusCode)
	}
}

func postJSON(t *testing.T, client *http.Client, base, key, body string) (int, map[string]any) {
	t.Helper()
	req, err := http.NewRequest(http.MethodPost, base+"/orders", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	if key != "" {
		req.Header.Set("Idempotency-Key", key)
	}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&out)
	return resp.StatusCode, out
}
