package order

import (
	"encoding/json"
	"testing"
	"time"
)

func BenchmarkEncodeOrder(b *testing.B) {
	o := Order{
		ID: "ord_benchmark", IdempotencyKey: "bench", AmountCents: 1990,
		Status: StatusPaid, Attempts: 1,
		CreatedAt: time.Date(2026, time.January, 1, 0, 0, 0, 0, time.UTC),
		UpdatedAt: time.Date(2026, time.January, 1, 0, 0, 1, 0, time.UTC),
	}
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		encoded, err := json.Marshal(o)
		if err != nil {
			b.Fatal(err)
		}
		if len(encoded) == 0 {
			b.Fatal("empty JSON")
		}
	}
}
