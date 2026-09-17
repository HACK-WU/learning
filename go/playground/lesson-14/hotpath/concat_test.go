package hotpath

import (
	"testing"
)

var benchmarkSink string

var benchmarkParts = []string{
	"order-", "001", "-", "paid", "-", "cn", "-", "east", "-", "2026",
}

func TestConcat(t *testing.T) {
	want := "order-001-paid-cn-east-2026"
	for name, got := range map[string]string{
		"naive":   ConcatNaive(benchmarkParts),
		"builder": ConcatBuilder(benchmarkParts),
	} {
		if got != want {
			t.Errorf("%s = %q, want %q", name, got, want)
		}
	}
}

// BenchmarkConcatNaive uses b.N because it makes the framework's iteration
// model visible. Assigning to benchmarkSink keeps the result observable.
func BenchmarkConcatNaive(b *testing.B) {
	for range b.N {
		benchmarkSink = ConcatNaive(benchmarkParts)
	}
}

// BenchmarkConcatBuilder measures the same behavior with a reusable builder
// inside each operation and an explicit capacity estimate.
func BenchmarkConcatBuilder(b *testing.B) {
	for range b.N {
		benchmarkSink = ConcatBuilder(benchmarkParts)
	}
}
