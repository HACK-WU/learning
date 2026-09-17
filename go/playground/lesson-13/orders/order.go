// Package orders contains the smallest useful slice of an order service.
package orders

import (
	"encoding/json"
	"errors"
	"net/http"
)

var (
	// ErrMissingID means that an order has no business identifier.
	ErrMissingID = errors.New("id is required")

	// ErrInvalidQuantity means that an order quantity is not positive.
	ErrInvalidQuantity = errors.New("quantity must be positive")
)

// Order is the JSON shape accepted by the order endpoint.
type Order struct {
	ID       string `json:"id"`
	Quantity int    `json:"quantity"`
}

// Validate checks the business rules that do not require a database.
func Validate(order Order) error {
	if order.ID == "" {
		return ErrMissingID
	}
	if order.Quantity <= 0 {
		return ErrInvalidQuantity
	}
	return nil
}

// Handler accepts a valid order and returns a small acknowledgement.
func Handler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	defer r.Body.Close()

	var order Order
	if err := json.NewDecoder(r.Body).Decode(&order); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	if err := Validate(order); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	_, _ = w.Write([]byte(`{"status":"accepted"}`))
}
