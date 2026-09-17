package order

import (
	"fmt"
	"sync/atomic"
)

type Metrics struct {
	HTTPRequests  atomic.Uint64
	HTTPFailures  atomic.Uint64
	OrdersCreated atomic.Uint64
	OrdersPaid    atomic.Uint64
	OrdersFailed  atomic.Uint64
	PaymentRetry  atomic.Uint64
}

func (m *Metrics) Render() string {
	return fmt.Sprintf(`# HELP order_http_requests_total Total HTTP requests.
# TYPE order_http_requests_total counter
order_http_requests_total %d
# HELP order_http_failures_total HTTP responses with status >= 400.
# TYPE order_http_failures_total counter
order_http_failures_total %d
# HELP order_created_total Orders accepted by the service.
# TYPE order_created_total counter
order_created_total %d
# HELP order_paid_total Orders successfully charged.
# TYPE order_paid_total counter
order_paid_total %d
# HELP order_failed_total Orders that exhausted payment attempts.
# TYPE order_failed_total counter
order_failed_total %d
# HELP order_payment_retry_total Payment retries started.
# TYPE order_payment_retry_total counter
order_payment_retry_total %d
`,
		m.HTTPRequests.Load(), m.HTTPFailures.Load(), m.OrdersCreated.Load(),
		m.OrdersPaid.Load(), m.OrdersFailed.Load(), m.PaymentRetry.Load())
}
