// Command demo exercises the order handler without opening a real network port.
package main

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"

	"example.com/go-course/lesson13/orders"
)

func main() {
	req := httptest.NewRequest(
		http.MethodPost,
		"http://example.com/orders",
		strings.NewReader(`{"id":"order-001","quantity":2}`),
	)
	rec := httptest.NewRecorder()

	orders.Handler(rec, req)

	fmt.Printf("status=%d body=%s\n", rec.Code, strings.TrimSpace(rec.Body.String()))
}
