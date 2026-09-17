package app

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"example.com/go-order-service/internal/order"
)

type testPayment struct{}

func (testPayment) Charge(context.Context, order.Order) error { return nil }

func TestPublicAndAdminSurfacesAreSeparated(t *testing.T) {
	store, err := order.OpenStore(context.Background(), "file:app_surface?mode=memory&cache=shared")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = store.Close() })
	a := New(store, testPayment{}, Config{Version: "test", PaymentTimeout: time.Second})
	a.Start(context.Background())
	t.Cleanup(func() {
		ctx, cancel := context.WithTimeout(context.Background(), time.Second)
		defer cancel()
		_ = a.Stop(ctx)
	})

	public := httptest.NewRecorder()
	a.PublicHandler().ServeHTTP(public, httptest.NewRequest(http.MethodGet, "/debug/pprof/", nil))
	if public.Code != http.StatusNotFound {
		t.Fatalf("public pprof status=%d", public.Code)
	}

	admin := httptest.NewRecorder()
	a.AdminHandler().ServeHTTP(admin, httptest.NewRequest(http.MethodGet, "/debug/pprof/", nil))
	if admin.Code != http.StatusOK {
		t.Fatalf("admin pprof status=%d", admin.Code)
	}
}
