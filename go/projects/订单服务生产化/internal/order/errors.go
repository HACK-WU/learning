package order

import "errors"

var (
	ErrNotFound            = errors.New("order not found")
	ErrIdempotencyConflict = errors.New("idempotency key already belongs to another amount")
	ErrQueueFull           = errors.New("order queue is full")
)
