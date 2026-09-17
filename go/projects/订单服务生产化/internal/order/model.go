package order

import "time"

// Status 是订单在异步履约链路中的状态。
type Status string

const (
	StatusPending    Status = "pending"
	StatusProcessing Status = "processing"
	StatusPaid       Status = "paid"
	StatusFailed     Status = "failed"
)

// Order 是 API、存储和支付客户端之间共享的业务模型。
type Order struct {
	ID             string    `json:"id"`
	IdempotencyKey string    `json:"idempotency_key"`
	AmountCents    int64     `json:"amount_cents"`
	Status         Status    `json:"status"`
	Attempts       int       `json:"attempts"`
	LastError      string    `json:"last_error,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

type CreateOrderRequest struct {
	AmountCents int64 `json:"amount_cents"`
}
